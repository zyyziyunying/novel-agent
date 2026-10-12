import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:novel_contracts/novel_contracts.dart';

Future<Process> spawnLibraryAgent(
  Directory directory, {
  bool fixture = false,
}) async {
  final packageConfig = (await Isolate.packageConfig)!;
  final library = (await Isolate.resolvePackageUri(
    Uri.parse('package:novel_agent/novel_agent.dart'),
  ))!;
  final entry = File.fromUri(
    library,
  ).parent.parent.uri.resolve('bin/novel_agent.dart');
  final environment = {...Platform.environment}
    ..remove('DEEPSEEK_API_KEY')
    ..remove('GENKIT_TELEMETRY_SERVER')
    ..remove('GENKIT_REFLECTION_V2_SERVER')
    ..remove('GENKIT_RUNTIME_ID')
    ..addAll({
      'GENKIT_ENV': 'dev',
      'NOVEL_AGENT_PORT': '0',
      'NOVEL_VIEWER_ORIGIN': 'http://localhost:4300',
      'NOVEL_DATA_DIR': '${directory.path}/data',
    });
  return Process.start(
    Platform.resolvedExecutable,
    [
      '--disable-dart-dev',
      '--packages=${packageConfig.toFilePath()}',
      entry.toFilePath(),
      if (fixture) '--fixture',
    ],
    workingDirectory: directory.path,
    environment: environment,
    includeParentEnvironment: false,
  );
}

class LibraryAgentProcess {
  LibraryAgentProcess(this.process, this.port, this.token);
  final Process process;
  final int port;
  final String token;
  final HttpClient client = HttpClient();

  static Future<LibraryAgentProcess> start(
    Directory directory, {
    bool fixture = false,
  }) async {
    final process = await spawnLibraryAgent(directory, fixture: fixture);
    final token = Completer<String>();
    var port = 0;
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'http://127\.0\.0\.1:(\d+)').firstMatch(line);
          if (match != null) {
            port = int.parse(match.group(1)!);
          }
          const prefix = '工作台会话令牌：';
          if (line.startsWith(prefix) && !token.isCompleted) {
            token.complete(line.substring(prefix.length));
          }
        });
    unawaited(
      process.exitCode.then((code) {
        if (!token.isCompleted) {
          token.completeError(StateError('启动失败 $code: $errors'));
        }
      }),
    );
    try {
      final session = await token.future.timeout(const Duration(seconds: 15));
      return LibraryAgentProcess(process, port, session);
    } on Object {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      rethrow;
    }
  }

  Future<(int, Json)> request(
    String path, {
    Object? body,
    String? bearer,
    String? origin,
    bool authenticated = true,
  }) async {
    final request = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    if (authenticated) {
      request.headers.set('authorization', 'Bearer ${bearer ?? token}');
    }
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 5));
    return (
      response.statusCode,
      jsonDecode(await response.transform(utf8.decoder).join()) as Json,
    );
  }

  Future<Json> execute(LibraryCommand command) async {
    final response = await request(
      '/libraryAction',
      body: {'data': command.toJson()},
    );
    if (response.$1 != 200) {
      throw StateError('HTTP ${response.$1}: ${response.$2}');
    }
    return response.$2['result'] as Json;
  }

  Future<int> stop({bool abrupt = false}) async {
    client.close(force: true);
    process.kill(abrupt ? ProcessSignal.sigkill : ProcessSignal.sigterm);
    return process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}
