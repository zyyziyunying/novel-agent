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
  if (!fixture && (env['DEEPSEEK_API_KEY'] ?? '').trim().isEmpty) {
    stderr.writeln('请设置 DEEPSEEK_API_KEY，或使用 --fixture 启动演示模式。');
    exitCode = 64;
    return;
  }
  final port = int.parse(env['NOVEL_AGENT_PORT'] ?? '4100');
  final origin = env['NOVEL_VIEWER_ORIGIN'] ?? 'http://localhost:4300';
  final directory = Directory(env['NOVEL_DATA_DIR'] ?? '.local/novel-data');
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
  // The SDK reflection server bypasses this entry point's session checks.
  final ai = Genkit(isDevEnv: false, plugins: fixture ? [] : [deepSeek()]);
  final repository = await FileWorkspaceRepository.open(
    '${directory.path}/workspace.json',
  );
  final model = fixture
      ? FixtureNovelModel()
      : DeepSeekNovelModel(
          ai,
          modelName: env['DEEPSEEK_MODEL'] ?? 'deepseek-flash',
        );
  final service = NovelService(repository, model);
  final runtime = NovelRuntime(ai, service);
  final router = GenkitRouter()..addAction(runtime.action);
  final token = base64UrlEncode(
    List.generate(32, (_) => Random.secure().nextInt(256)),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Novel Agent: http://127.0.0.1:$port · ${model.name}');
  // Local session token is printed once; it is not a provider key.
  stdout.writeln('工作台会话令牌：$token');
  stdout.writeln('Flutter 启动参数：--dart-define=NOVEL_AGENT_TOKEN=$token');
  Future<void> stop() async {
    await server.close(force: true);
    await lock.close();
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
        snapshotPath: '/workspace',
        origin: origin,
        token: token,
      ),
    );
  }
}
