import 'dart:convert';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';

Matcher failure(String code) =>
    isA<LibraryFailure>().having((e) => e.code, 'code', code);

void main() {
  late InMemoryLibraryRepository repository;
  late LibraryService service;
  setUp(() {
    repository = InMemoryLibraryRepository();
    service = LibraryService(repository);
  });

  Future<void> seed() async {
    await service.execute(createWork());
    await service.execute(createLibrary());
  }

  test('无模型从空工作区创建目标、保存原文和来源，不自动采用资料', () async {
    final initial = await service.snapshot();
    expect(initial['workspace']['revision'], 0);
    expect(initial['workspace']['works'], isEmpty);
    expect(initial['provider'], isNull);
    expect(initial['modelAvailable'], isFalse);
    await seed();
    final result = await service.execute(saveDocument(2));
    expect(result['reused'], isFalse);
    final workspace = await repository.load();
    expect(workspace.revision, 3);
    expect(workspace.receipts.length, 3);
    expect(
      workspace.receipts['save-v1']!.target.toJson(),
      CommandTarget.library('library-a', workId: 'work-a').toJson(),
    );
    final version = workspace.libraries.single.documents.single.current;
    expect(version.toJson(), saveDocument(2).payload['version']);
    expect(workspace.works.single.knowledgeLinks, isEmpty);
    expect(workspace.works.single.chapters, isEmpty);
    expect(workspace.works.single.memories, isEmpty);
  });

  test('作品、知识库及资料 ID 的归属独立；重命名保留全部内容', () async {
    await seed();
    await service.execute(saveDocument(2));
    await service.execute(createWork(3, 'work-b'));
    await service.execute(createLibrary(4, 'library-b'));
    await service.execute(
      saveDocument(
        5,
        requestId: 'save-b',
        libraryId: 'library-b',
        workId: 'work-b',
        body: '另一作品资料',
      ),
    );
    await service.execute(
      command('rename-a', 6, 'renameWork', {
        'title': '  更名 A  ',
      }, target: CommandTarget.work('work-a')),
    );
    await service.execute(
      command(
        'rename-library',
        7,
        'renameLibrary',
        {'name': '  共享资料库  '},
        target: CommandTarget.library('library-a'),
      ),
    );
    final workspace = await repository.load();
    expect(workspace.work('work-a').title, '  更名 A  ');
    expect(workspace.work('work-b').title, '作品 work-b');
    expect(workspace.library('library-a').name, '  共享资料库  ');
    expect(workspace.library('library-a').documents.single.versions.length, 1);
    expect(
      workspace.library('library-b').documents.single.current.body,
      '另一作品资料',
    );
    expect(workspace.revision, 8);
    expect(workspace.receipts.length, 8);
  });

  test('资料更新只追加历史，保留旧版本与来源', () async {
    await seed();
    await service.execute(saveDocument(2));
    await service.execute(
      saveDocument(
        3,
        requestId: 'save-v2',
        versionId: 'v2',
        previous: 'v1',
        body: '新版',
      ),
    );
    final document =
        (await repository.load()).libraries.single.documents.single;
    expect(document.head, 'v2');
    expect(document.versions.map((v) => v.id), ['v1', 'v2']);
    expect(
      document.versions.first.toJson(),
      saveDocument(2).payload['version'],
    );
    expect(document.current.body, '新版');
  });

  test('同请求并发或响应丢失后重试只提交一次，返回当前快照', () async {
    await seed();
    final original = saveDocument(2);
    final results = await Future.wait(
      List.generate(8, (_) => service.execute(original)),
    );
    expect(results.where((r) => r['reused'] == false).length, 1);
    expect(results.where((r) => r['reused'] == true).length, 7);
    await service.execute(createWork(3, 'work-b'));
    final replay = await service.execute(original);
    expect(replay['reused'], isTrue);
    expect(replay['workspace']['revision'], 4);
    expect(
      (await repository.load())
          .libraries
          .single
          .documents
          .single
          .versions
          .length,
      1,
    );
  });

  test('回执先于旧修订和目标条件检查，同 ID 不同内容全局冲突', () async {
    await seed();
    await service.execute(saveDocument(2));
    await expectLater(
      service.execute(saveDocument(0, body: '更改请求')),
      throwsA(failure('request_conflict')),
    );
    await expectLater(
      service.execute(
        command('save-v1', 0, 'renameWork', {
          'title': '不同目标',
        }, target: CommandTarget.work('missing')),
      ),
      throwsA(failure('request_conflict')),
    );
    expect((await service.execute(saveDocument(2)))['reused'], isTrue);
    expect((await repository.load()).revision, 3);
  });

  test('对象键排列不影响回执指纹', () async {
    await service.execute(createWork());
    final reordered = LibraryCommand.fromJson({
      'payload': {'title': '作品 work-a', 'id': 'work-a'},
      'target': {'kind': 'catalog'},
      'operation': 'createWork',
      'expectedRevision': 0,
      'requestId': 'create-work-a',
      'apiVersion': 2,
    });
    expect((await service.execute(reordered))['reused'], isTrue);
    expect((await repository.load()).revision, 1);
  });

  test('相同修订的不同并发请求只允许一个成功，不覆盖另一个', () async {
    final outcomes = await Future.wait(
      [createWork(), createWork(0, 'work-b')].map((c) async {
        try {
          await service.execute(c);
          return 'saved';
        } on LibraryFailure catch (e) {
          return e.code;
        }
      }),
    );
    expect(outcomes, ['saved', 'version_conflict']);
    expect((await repository.load()).works.map((w) => w.id), ['work-a']);
    expect((await repository.load()).receipts.length, 1);
  });

  test('重复对象 ID、缺失目标和旧修订不改变快照或新增回执', () async {
    await seed();
    final before = (await repository.load()).toJson();
    await expectLater(
      service.execute(
        command('duplicate', 2, 'createWork', {'id': 'work-a', 'title': '覆盖'}),
      ),
      throwsA(failure('target_exists')),
    );
    await expectLater(
      service.execute(
        command('duplicate-library', 2, 'createLibrary', {
          'id': 'library-a',
          'name': '覆盖',
        }),
      ),
      throwsA(failure('target_exists')),
    );
    await expectLater(
      service.execute(saveDocument(2, libraryId: 'missing')),
      throwsA(failure('target_missing')),
    );
    await expectLater(
      service.execute(saveDocument(2, workId: 'missing')),
      throwsA(failure('target_missing')),
    );
    await expectLater(
      service.execute(saveDocument(1)),
      throwsA(failure('version_conflict')),
    );
    expect((await repository.load()).toJson(), before);
  });

  test('资料新增 null、更新 head 和未使用版本 ID 的前置条件均执行', () async {
    await seed();
    await expectLater(
      service.execute(saveDocument(2, previous: 'missing')),
      throwsA(failure('version_conflict')),
    );
    await service.execute(saveDocument(2));
    await expectLater(
      service.execute(
        saveDocument(3, requestId: 'wrong-create', versionId: 'v2'),
      ),
      throwsA(failure('version_conflict')),
    );
    await service.execute(
      saveDocument(3, requestId: 'save-v2', versionId: 'v2', previous: 'v1'),
    );
    final before = (await repository.load()).toJson();
    await expectLater(
      service.execute(
        saveDocument(4, requestId: 'stale', versionId: 'v3', previous: 'v1'),
      ),
      throwsA(failure('version_conflict')),
    );
    await expectLater(
      service.execute(
        saveDocument(4, requestId: 'old-id', versionId: 'v1', previous: 'v2'),
      ),
      throwsA(failure('version_conflict')),
    );
    expect((await repository.load()).toJson(), before);
  });

  test('未关联作品的资料可以独立写入', () async {
    await service.execute(createLibrary(0));
    await service.execute(saveDocument(1, workId: null));
    expect((await repository.load()).works, isEmpty);
    expect(
      (await repository.load())
          .libraries
          .single
          .documents
          .single
          .current
          .associatedWorkId,
      isNull,
    );
  });

  test('不存在的讨论来源拒绝保存，不授予资料指令权限', () async {
    await seed();
    final json = jsonDecode(jsonEncode(saveDocument(2).toJson())) as Json;
    json['payload']['version']['provenance']['sources'] = [
      {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'missing',
        'messageId': 'm1',
      },
    ];
    await expectLater(
      service.execute(LibraryCommand.fromJson(json)),
      throwsA(failure('invalid_reference')),
    );
    expect((await repository.load()).revision, 2);
    expect((await repository.load()).libraries.single.documents, isEmpty);
  });

  test('无模型操作显式不可用，之后仍能保存资料；已配置模型不被资料保存调用', () async {
    await seed();
    final generate = command('generate', 2, 'proposeChapter', {
      'instruction': '续写',
    }, target: CommandTarget.work('work-a'));
    await expectLater(
      service.execute(generate),
      throwsA(failure('model_unavailable')),
    );
    service = LibraryService(repository, model: NeverCalledModel());
    await service.execute(saveDocument(2));
    expect((await repository.load()).revision, 3);
    expect((await service.snapshot())['modelAvailable'], isTrue);
  });

  test('作品可关联空知识库而不采用资料，关联操作保存目标回执', () async {
    await seed();
    await service.execute(
      command('links', 2, 'setKnowledgeLinks', {
        'links': [LibraryLink(libraryId: 'library-a', versions: {}).toJson()],
      }, target: CommandTarget.work('work-a')),
    );
    expect((await repository.load()).work('work-a').adoptedDocuments, isEmpty);
    expect((await repository.load()).receipts.keys, [
      'create-work-a',
      'create-library-a',
      'links',
    ]);
  });

  test('模型写作失败后仍可由工具新增与更新资料，保存不再调用模型', () async {
    await seed();
    service = LibraryService(repository, model: NeverCalledModel());
    final before = (await repository.load()).work('work-a').toJson();
    await expectLater(
      service.execute(
        command(
          'failed-generation',
          2,
          'proposeChapter',
          {'instruction': '起草第一章'},
          target: CommandTarget.work('work-a'),
        ),
      ),
      throwsA(failure('model_failed')),
    );
    expect((await repository.load()).revision, 2);
    await service.execute(saveDocument(2));
    await service.execute(
      saveDocument(
        3,
        requestId: 'after-failure-update',
        previous: 'v1',
        versionId: 'v2',
        body: '工具更新的资料',
      ),
    );
    final workspace = await repository.load();
    expect(workspace.library('library-a').documents.single.head, 'v2');
    expect(workspace.library('library-a').documents.single.versions.length, 2);
    expect(workspace.work('work-a').toJson(), before);
    expect(workspace.receipts.containsKey('failed-generation'), isFalse);
    expect((await service.execute(saveDocument(2)))['reused'], isTrue);
  });

  test('仓库 CAS 冲突转换为版本冲突，失败后队列可继续工作', () async {
    final store = ConflictingRepository();
    final service = LibraryService(store);
    await expectLater(
      service.execute(createWork()),
      throwsA(failure('version_conflict')),
    );
    expect(store.workspace.revision, 0);
    store.conflict = false;
    await service.execute(createWork());
    expect(store.workspace.revision, 1);
  });
}

class ConflictingRepository extends InMemoryLibraryRepository {
  bool conflict = true;
  @override
  Future<void> save(LibraryWorkspace workspace, int expectedRevision) async {
    if (conflict) throw const LibraryRepositoryConflict();
    await super.save(workspace, expectedRevision);
  }
}

class NeverCalledModel implements NovelModel {
  @override
  String get name => 'test-model';
  @override
  Future<ModelDraft> write(
    Json context,
    String instruction, {
    bool edit = false,
  }) => throw StateError('资料服务不能调用模型');
  @override
  Future<List<StoryFact>> extract(Workspace workspace) =>
      throw StateError('资料服务不能调用模型');
}
