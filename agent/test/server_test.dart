import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('工作台接口保持会话鉴权并隔离重复请求头和断开连接', () async {
    final directory = await Directory.systemTemp.createTemp(
      'novel-server-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}/pubspec.yaml',
    ).writeAsString('name: isolated_test\n');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final packageConfig = (await Isolate.packageConfig)!;
    final library = (await Isolate.resolvePackageUri(
      Uri.parse('package:novel_agent/novel_agent.dart'),
    ))!;
    final entry = File.fromUri(
      library,
    ).parent.parent.uri.resolve('bin/prototype_agent.dart');
    final environment = {...Platform.environment}
      ..remove('DEEPSEEK_API_KEY')
      ..remove('GENKIT_TELEMETRY_SERVER')
      ..remove('GENKIT_REFLECTION_V2_SERVER')
      ..remove('GENKIT_RUNTIME_ID')
      ..addAll({
        'GENKIT_ENV': 'dev',
        'NOVEL_AGENT_PORT': '$port',
        'NOVEL_VIEWER_ORIGIN': 'http://localhost:4300',
        'NOVEL_DATA_DIR': '${directory.path}/data',
      });
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        '--disable-dart-dev',
        '--packages=${packageConfig.toFilePath()}',
        entry.toFilePath(),
        '--fixture',
      ],
      workingDirectory: directory.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    addTearDown(() async {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    });
    final token = Completer<String>();
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          const prefix = '工作台会话令牌：';
          if (line.startsWith(prefix) && !token.isCompleted) {
            token.complete(line.substring(prefix.length));
          }
        });
    final errors = process.stderr.drain<void>();
    addTearDown(output.cancel);
    final session = await token.future.timeout(const Duration(seconds: 15));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<(int, Map<String, dynamic>)> request(
      String path, {
      String? bearer,
      String? origin,
      Object? body,
    }) async {
      final request = await client.openUrl(
        body == null ? 'GET' : 'POST',
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      if (bearer != null) {
        request.headers.set('authorization', 'Bearer $bearer');
      }
      if (origin != null) request.headers.set('origin', origin);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      return (
        response.statusCode,
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>,
      );
    }

    Future<int> rawRequest(
      List<String> headers, {
      String method = 'GET',
    }) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      try {
        socket.write(
          '$method /workspace HTTP/1.1\r\n'
          'Host: 127.0.0.1:$port\r\n'
          'Connection: close\r\n'
          '${headers.join('\r\n')}\r\n\r\n',
        );
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        final status = RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(response);
        expect(status, isNotNull, reason: '服务应返回 HTTP 响应。');
        return int.parse(status!.group(1)!);
      } finally {
        socket.destroy();
      }
    }

    expect((await request('/workspace')).$1, 401);
    expect(
      (await request(
        '/workspace',
        bearer: session,
        origin: 'https://unauthorized.example',
      )).$1,
      403,
    );
    expect(
      (await request(
        '/workspace',
        bearer: session,
        origin: 'http://localhost:4300',
      )).$1,
      200,
    );
    final preflight = await client.openUrl(
      'OPTIONS',
      Uri.parse('http://127.0.0.1:$port/novelAction'),
    );
    preflight.headers.set('origin', 'http://localhost:4300');
    preflight.headers.set('access-control-request-method', 'POST');
    preflight.headers.set(
      'access-control-request-headers',
      'authorization,content-type',
    );
    final preflightResponse = await preflight.close();
    expect(preflightResponse.statusCode, 204);
    expect(
      preflightResponse.headers.value('access-control-allow-origin'),
      'http://localhost:4300',
    );
    expect(
      preflightResponse.headers.value('access-control-allow-headers'),
      'authorization,content-type',
    );
    expect(
      preflightResponse.headers.value('access-control-allow-methods'),
      'GET,POST,OPTIONS',
    );
    await preflightResponse.drain<void>();

    final malformedHeaders = [
      [
        'Origin: http://localhost:4300',
        'Origin: http://localhost:4300',
        'Authorization: Bearer $session',
      ],
      [
        'Origin: http://localhost:4300',
        'Origin: https://unauthorized.example',
        'Authorization: Bearer $session',
      ],
      ['Authorization: Bearer $session', 'Authorization: Bearer invalid'],
      ['Authorization: Bearer invalid', 'Authorization: Bearer $session'],
    ];
    for (var index = 0; index < malformedHeaders.length; index++) {
      expect(await rawRequest(malformedHeaders[index]), 400);
      expect(exited, isFalse, reason: '非法请求头不能终止服务。');
      expect((await request('/workspace', bearer: session)).$1, 200);
    }
    expect(await rawRequest(malformedHeaders.last, method: 'OPTIONS'), 400);
    expect((await request('/workspace', bearer: session)).$1, 200);

    for (final path in ['/workspace', '/novelAction']) {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.write(
        '${path == '/workspace' ? 'GET' : 'POST'} $path HTTP/1.1\r\n'
        'Host: 127.0.0.1:$port\r\n'
        'Origin: http://localhost:4300\r\n'
        'Authorization: Bearer $session\r\n'
        '${path == '/novelAction' ? 'Content-Length: 1000\r\n' : ''}'
        '\r\n'
        '${path == '/novelAction' ? '{' : ''}',
      );
      await socket.flush();
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(exited, isFalse, reason: '客户端断开连接不能终止服务。');
      expect((await request('/workspace', bearer: session)).$1, 200);
    }
    final command = {
      'data': {
        'requestId': 'authorized-save',
        'expectedRevision': 0,
        'operation': 'saveChapter',
        'payload': {'chapterId': 'chapter-1', 'body': '经过会话鉴权保存的正文。'},
      },
    };
    expect((await request('/novelAction', body: command)).$1, 401);
    final result = await request(
      '/novelAction',
      bearer: session,
      body: command,
    );
    expect(result.$1, 200);
    expect(result.$2['result']['workspace']['revision'], 1);
    final store = jsonDecode(
      await File('${directory.path}/data/workspace.json').readAsString(),
    );
    expect(store['chapters'][0]['versions'].last['body'], '经过会话鉴权保存的正文。');
    // Give the SDK's asynchronous reflection startup time to advertise a runtime.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final runtimes = Directory('${directory.path}/.genkit/runtimes');
    expect(
      await runtimes.exists() ? await runtimes.list().toList() : [],
      isEmpty,
    );
    process.kill(ProcessSignal.sigterm);
    expect(await process.exitCode, 0);
    await errors;
  }, timeout: const Timeout(Duration(seconds: 25)));
}
