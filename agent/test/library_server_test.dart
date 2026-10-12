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

  test(
    '无模型 HTTP 新建空白章节，强制重启保留并可手动保存；重试不重复建章',
    () async {
      var server = await LibraryAgentProcess.start(directory);
      addTearDown(() => server.stop());
      await server.execute(createWork());
      final original = command('manual-http', 1, 'createChapter', {
        'chapterId': 'manual-first',
        'title': '作者的第一章',
      }, target: CommandTarget.work('work-a'));
      await server.execute(original);
      final before = (await server.request(
        '/libraryWorkspace',
      )).$2['workspace'];
      await server.stop(abrupt: true);
      server = await LibraryAgentProcess.start(directory);
      final loaded = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      expect(loaded.toJson(), before);
      expect(loaded.work('work-a').chapters.single.body, isEmpty);
      expect((await server.execute(original))['reused'], isTrue);
      final saved = await server.execute(
        command('manual-save', 2, 'saveChapter', {
          'chapterId': 'manual-first',
          'body': '完全由作者手写的正文。',
        }, target: CommandTarget.work('work-a')),
      );
      final work = LibraryWorkspace.fromJson(saved['workspace']).work('work-a');
      expect(work.chapters.single.title, '作者的第一章');
      expect(work.chapters.single.body, '完全由作者手写的正文。');
      expect(work.chapters.single.versions.length, 2);
      expect(work.chapters.single.versions.first.body, isEmpty);
      expect(work.proposals, isEmpty);
      expect(saved['modelAvailable'], isFalse);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

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

  test('fixture 显式启用后可起草格式 2 正文', () async {
    final server = await LibraryAgentProcess.start(directory, fixture: true);
    addTearDown(server.stop);
    final state = (await server.request('/libraryWorkspace')).$2;
    expect(state['modelAvailable'], isTrue);
    expect(state['provider'], 'fixture/local');
    await server.execute(createWork());
    final generate = command('generate', 1, 'proposeChapter', {
      'instruction': '续写',
    }, target: CommandTarget.work('work-a'));
    final response = await server.execute(generate);
    expect(response['workspace']['works'][0]['proposals'].length, 1);
    await server.execute(createLibrary(2));
    expect(
      (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
      3,
    );
    expect(await server.stop(), 0);
  }, timeout: const Timeout(Duration(seconds: 25)));

  test(
    '两作品的正文、命名、历史、提案、记忆和目标回执在强制重启后保留',
    () async {
      var server = await LibraryAgentProcess.start(directory, fixture: true);
      addTearDown(() => server.stop());
      await server.execute(createWork());
      await server.execute(createWork(1, 'work-b'));
      var revision = 2;
      var sequence = 0;
      Future<Json> act(
        String workId,
        String operation, [
        Json payload = const {},
      ]) async {
        final result = await server.execute(
          command(
            'm3-http-${++sequence}',
            revision,
            operation,
            payload,
            target: CommandTarget.work(workId),
          ),
        );
        revision = result['workspace']['revision'];
        return result;
      }

      for (final id in ['work-a', 'work-b']) {
        await act(id, 'renameWork', {'title': id == 'work-a' ? '远航记' : '长安夜'});
        final proposed = await act(id, 'proposeChapter', {
          'instruction': '第一章',
        });
        final work = LibraryWorkspace.fromJson(proposed['workspace']).work(id);
        await act(id, 'acceptProposal', {
          'proposalId': work.proposals.single.proposal.id,
        });
        await act(id, 'rebuildMemory');
        await act(id, 'saveChapter', {
          'chapterId': 'chapter-1',
          'body': '$id 作者保存正文。',
        });
        await act(id, 'rebuildMemory');
      }
      final before = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      await server.stop(abrupt: true);
      server = await LibraryAgentProcess.start(directory);
      final after = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      expect(after.toJson(), before.toJson());
      expect(after.works.map((w) => w.title), ['远航记', '长安夜']);
      for (final id in ['work-a', 'work-b']) {
        expect(after.work(id).chapters.single.body, '$id 作者保存正文。');
        expect(after.work(id).chapters.single.versions.length, 2);
        expect(after.work(id).proposals.single.workId, id);
        expect(
          after.workView(id).currentMemory!.facts.single.evidence,
          '$id 作者保存正文。',
        );
      }
      final retry = command(
        'm3-http-$sequence',
        before.revision - 1,
        'rebuildMemory',
        {},
        target: CommandTarget.work('work-b'),
      );
      expect((await server.execute(retry))['reused'], isTrue);
      expect(
        (await server.request('/libraryWorkspace')).$2['modelAvailable'],
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
