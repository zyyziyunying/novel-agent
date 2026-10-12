import 'dart:convert';
import 'dart:io';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';
import 'support/library_server.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('library-server-');
    await File(
      '${directory.path}/pubspec.yaml',
    ).writeAsString('name: isolated_library_test\n');
  });
  tearDown(() => directory.delete(recursive: true));

  test('无密钥 HTTP 读写、原文来源、强制重启与原请求回执去重', () async {
    var server = await LibraryAgentProcess.start(directory);
    addTearDown(() => server.stop());
    final initial = await server.request('/libraryWorkspace');
    expect(initial.$1, 200);
    expect(initial.$2['modelAvailable'], isFalse);
    expect(initial.$2['provider'], isNull);
    expect(initial.$2['workspace'], {
      'schemaVersion': 2,
      'revision': 0,
      'works': [],
      'libraries': [],
      'receipts': {},
    });
    await server.execute(createWork());
    await server.execute(createLibrary());
    final original = saveDocument(2);
    await server.execute(original);
    final before = (await server.request('/libraryWorkspace')).$2['workspace'];
    final oldToken = server.token;
    await server.stop(abrupt: true);
    server = await LibraryAgentProcess.start(directory);
    expect((await server.request('/libraryWorkspace')).$2['workspace'], before);
    expect(
      (await server.request('/libraryWorkspace', bearer: oldToken)).$1,
      401,
    );
    final replay = await server.execute(original);
    expect(replay['reused'], isTrue);
    expect(replay['workspace'], before);
    expect(
      await File('${directory.path}/data/workspace.json').exists(),
      isFalse,
    );
    expect((await server.request('/workspace')).$1, 404);
    final runtimes = Directory('${directory.path}/.genkit/runtimes');
    expect(
      await runtimes.exists() ? await runtimes.list().toList() : [],
      isEmpty,
    );
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('鉴权、来源与非法请求失败不修改快照；无模型错误后仍可保存', () async {
    final server = await LibraryAgentProcess.start(directory);
    addTearDown(server.stop);
    final original = createWork();
    expect(
      (await server.request('/libraryWorkspace', authenticated: false)).$1,
      401,
    );
    expect(
      (await server.request(
        '/libraryAction',
        authenticated: false,
        body: {'data': original.toJson()},
      )).$1,
      401,
    );
    expect(
      (await server.request(
        '/libraryAction',
        origin: 'https://unauthorized.example',
        body: {'data': original.toJson()},
      )).$1,
      403,
    );
    final before = (await server.request('/libraryWorkspace')).$2['workspace'];
    for (final body in [
      {
        'data': {...original.toJson(), 'unknown': true},
      },
      {
        'data': {...original.toJson(), 'apiVersion': 1},
      },
      {
        'data': {...original.toJson(), 'expectedRevision': '0'},
      },
      {
        'data': {
          ...original.toJson(),
          'target': {'kind': 'work', 'workId': 'wrong'},
        },
      },
    ]) {
      final response = await server.request('/libraryAction', body: body);
      expect(response.$1, greaterThanOrEqualTo(400));
      expect(
        (await server.request('/libraryWorkspace')).$2['workspace'],
        before,
      );
    }
    await server.execute(original);
    final generate = command('generate', 1, 'proposeChapter', {
      'instruction': '续写',
    }, target: CommandTarget.work('work-a'));
    final unavailable = await server.request(
      '/libraryAction',
      body: {'data': generate.toJson()},
    );
    expect(unavailable.$1, 400);
    expect(unavailable.$2['status'], 'FAILED_PRECONDITION');
    expect(unavailable.$2['message'], contains('未配置模型'));
    await server.execute(createLibrary());
    await server.execute(saveDocument(2));
    expect(
      (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
      3,
    );
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('HTTP 冲突、并发重试与写入失败恢复不产生重复版本', () async {
    final server = await LibraryAgentProcess.start(directory);
    addTearDown(server.stop);
    await server.execute(createWork());
    await server.execute(createLibrary());
    final original = saveDocument(2);
    final before = (await server.request('/libraryWorkspace')).$2['workspace'];
    final blocked = await Directory(
      '${directory.path}/data/library-workspace.json.tmp',
    ).create();
    expect(
      (await server.request(
        '/libraryAction',
        body: {'data': original.toJson()},
      )).$1,
      500,
    );
    expect((await server.request('/libraryWorkspace')).$2['workspace'], before);
    await blocked.delete();
    final results = await Future.wait(
      List.generate(4, (_) => server.execute(original)),
    );
    expect(results.where((r) => r['reused'] == false).length, 1);
    expect(results.where((r) => r['reused'] == true).length, 3);
    final changed = saveDocument(2, body: '不同内容');
    final conflict = await server.request(
      '/libraryAction',
      body: {'data': changed.toJson()},
    );
    expect(conflict.$1, 409);
    expect(conflict.$2['status'], 'ABORTED');
    expect(conflict.$2['message'], contains('同一个请求编号'));
    final stale = saveDocument(3, requestId: 'stale', versionId: 'v2');
    final rejected = await server.request(
      '/libraryAction',
      body: {'data': stale.toJson()},
    );
    expect(rejected.$1, 409);
    expect(rejected.$2['status'], 'ABORTED');
    expect(rejected.$2['message'], contains('资料版本已改变'));
    final workspace = (await server.request(
      '/libraryWorkspace',
    )).$2['workspace'];
    expect(workspace['revision'], 3);
    expect(workspace['libraries'][0]['documents'][0]['versions'].length, 1);
    expect(workspace['receipts'].length, 3);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test('同目录第二个服务先拒绝写锁，首个服务仍可继续保存', () async {
    final server = await LibraryAgentProcess.start(directory);
    addTearDown(server.stop);
    final file = File('${directory.path}/data/library-workspace.json');
    final before = await file.readAsString();
    final second = await spawnLibraryAgent(directory);
    final output = second.stdout.drain<void>();
    final errors = second.stderr.transform(utf8.decoder).join();
    expect(await second.exitCode.timeout(const Duration(seconds: 15)), 73);
    await output;
    expect(await errors, contains('数据目录已有 Agent 占用'));
    expect(await file.readAsString(), before);
    await server.execute(createWork());
    expect(
      (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
      1,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('损坏快照阻止启动，保留原文；纠正后释放锁可再次启动', () async {
    final data = await Directory('${directory.path}/data').create();
    final file = File('${data.path}/library-workspace.json');
    await file.writeAsString('{broken');
    final process = await spawnLibraryAgent(directory);
    final output = process.stdout.drain<void>();
    final errors = process.stderr.transform(utf8.decoder).join();
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 74);
    await output;
    expect(await errors, contains('已有快照不会重置'));
    expect(await file.readAsString(), '{broken');
    await file.delete();
    final server = await LibraryAgentProcess.start(directory);
    addTearDown(server.stop);
    expect(
      (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
      0,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'fixture 只能显式启用，格式 2 模型操作仍明确报告尚未接入',
    () async {
      final server = await LibraryAgentProcess.start(directory, fixture: true);
      addTearDown(server.stop);
      final state = (await server.request('/libraryWorkspace')).$2;
      expect(state['modelAvailable'], isTrue);
      expect(state['provider'], 'fixture/local');
      await server.execute(createWork());
      final generate = command('generate', 1, 'proposeChapter', {
        'instruction': '续写',
      }, target: CommandTarget.work('work-a'));
      final response = await server.request(
        '/libraryAction',
        body: {'data': generate.toJson()},
      );
      expect(response.$2['status'], 'FAILED_PRECONDITION');
      expect(response.$2['message'], contains('尚未接入格式 2 服务'));
      await server.execute(createLibrary());
      expect(
        (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
        2,
      );
      expect(await server.stop(), 0);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
