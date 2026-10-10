import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:novel_agent/novel_agent.dart';

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
    unawaited(_handle(request, router, service, origin, token));
  }
}

Future<void> _handle(
  HttpRequest request,
  GenkitRouter router,
  NovelService service,
  String origin,
  String token,
) async {
  try {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    final callers = request.headers['origin'];
    final authorizations = request.headers['authorization'];
    if ((callers?.length ?? 0) > 1 || (authorizations?.length ?? 0) > 1) {
      response.statusCode = 400;
      response.write(
        jsonEncode({
          'error': {'message': 'Origin 和 Authorization 请求头不能重复。'},
        }),
      );
      await response.close();
      return;
    }
    final caller = callers?.single;
    if (caller != null && caller != origin) {
      response.statusCode = 403;
      response.write(
        jsonEncode({
          'error': {'message': '不允许这个工作台来源。'},
        }),
      );
      await response.close();
      return;
    }
    if (caller == origin) {
      response.headers.set('access-control-allow-origin', origin);
      response.headers.set('vary', 'Origin');
      response.headers.set(
        'access-control-allow-headers',
        'authorization,content-type',
      );
      response.headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');
    }
    if (request.method == 'OPTIONS') {
      response.statusCode = 204;
      await response.close();
      return;
    }
    if (authorizations?.single != 'Bearer $token') {
      response.statusCode = 401;
      response.write(
        jsonEncode({
          'error': {'message': '会话令牌不正确，请使用 Agent 启动时显示的令牌。'},
        }),
      );
      await response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/workspace') {
      response.write(jsonEncode(await service.snapshot()));
      await response.close();
      return;
    }
    if (await router.handleHttpRequest(request)) return;
    response.statusCode = 404;
    response.write(
      jsonEncode({
        'error': {'message': '接口不存在。'},
      }),
    );
    await response.close();
  } on Object {
    try {
      request.response.statusCode = 500;
      request.response.write(
        jsonEncode({
          'error': {'message': '读取或处理作品失败。'},
        }),
      );
    } on Object {
      // The response may already be committed or the client disconnected.
    }
    try {
      await request.response.close();
    } on Object {
      // A failed cleanup must not escape this unawaited request handler.
    }
  }
}
