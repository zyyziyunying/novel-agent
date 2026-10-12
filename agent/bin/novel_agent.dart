import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:novel_agent/novel_agent.dart';
import 'package:novel_agent/src/local_http.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final fixture = args.contains('--fixture');
  final configured = (env['DEEPSEEK_API_KEY'] ?? '').trim().isNotEmpty;
  final port = int.parse(env['NOVEL_AGENT_PORT'] ?? '4100');
  final origin = env['NOVEL_VIEWER_ORIGIN'] ?? 'http://localhost:4300';
  final directory = Directory(
    env['NOVEL_DATA_DIR'] ?? '.local/workbench-web-data',
  );
  await directory.create(recursive: true);
  // Reject a second writer before reading or creating the store.
  final lock = await File(
    '${directory.path}/agent.lock',
  ).open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
  } on FileSystemException {
    stderr.writeln('数据目录已有 Agent 占用，请停止它或使用另一个 NOVEL_DATA_DIR。');
    await lock.close();
    exitCode = 73;
    return;
  }
  try {
    // The SDK reflection server bypasses this entry point's session checks.
    final ai = Genkit(
      isDevEnv: false,
      plugins: !fixture && configured ? [deepSeek()] : [],
    );
    final repository = await FileLibraryRepository.open(
      '${directory.path}/library-workspace.json',
    );
    final NovelModel? model = fixture
        ? FixtureNovelModel()
        : configured
        ? DeepSeekNovelModel(
            ai,
            modelName: env['DEEPSEEK_MODEL'] ?? 'deepseek-flash',
          )
        : null;
    final service = LibraryService(repository, model: model);
    await service.initialize();
    final runtime = LibraryRuntime(ai, service);
    final router = GenkitRouter()..addAction(runtime.action);
    final token = base64UrlEncode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    stdout.writeln(
      'Novel Agent: http://127.0.0.1:${server.port} · ${model?.name ?? '未配置模型；资料服务可用'}',
    );
    // Local session token is printed once; it is not a provider key.
    stdout.writeln('工作台会话令牌：$token');
    stdout.writeln('格式 2 接口：GET /libraryWorkspace · POST /libraryAction');
    Future<void> stop() async {
      await server.close(force: true);
      // Process exit releases the directory lock; finally handles startup failure.
      exit(0);
    }

    ProcessSignal.sigint.watch().listen((_) => unawaited(stop()));
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop()));
    await for (final request in server) {
      unawaited(
        handleLocalRequest(
          request,
          router: router,
          snapshot: service.snapshot,
          snapshotPath: '/libraryWorkspace',
          origin: origin,
          token: token,
        ),
      );
    }
  } on FormatException {
    stderr.writeln('工作区格式无效，拒绝启动；已有快照不会重置。');
    exitCode = 74;
  } on Object {
    stderr.writeln('Agent 启动或运行失败；请检查端口与工作区文件，已有快照不会重置。');
    exitCode = 74;
  } finally {
    await lock.close();
  }
}
