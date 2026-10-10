import 'dart:async';
import 'dart:io';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryWorkspaceRepository repository;
  late RecordingModel model;
  late NovelService service;
  var sequence = 0;
  setUp(() {
    repository = InMemoryWorkspaceRepository(demoWorkspace());
    model = RecordingModel();
    service = NovelService(repository, model);
    sequence = 0;
  });
  NovelCommand command(String operation, [Json payload = const {}]) =>
      NovelCommand(
        requestId: 'request-${++sequence}',
        expectedRevision: repository.workspace.revision,
        operation: operation,
        payload: payload,
      );
  Future<Json> run(String operation, [Json payload = const {}]) =>
      service.execute(command(operation, payload));
  Matcher failure(String code) =>
      isA<NovelFailure>().having((e) => e.code, 'code', code);

  test('起草和拒绝不会改变正文或已确认记忆', () async {
    final before = repository.workspace;
    await run('proposeChapter', {'instruction': '续写'});
    final proposal = repository.workspace.proposals.single;
    expect(repository.workspace.currentHeads, before.currentHeads);
    expect(repository.workspace.currentMemory!.id, before.currentMemory!.id);
    await run('rejectProposal', {'proposalId': proposal.id});
    expect(
      repository.workspace.chapters.first.body,
      before.chapters.first.body,
    );
    expect(repository.workspace.proposals.single.status, 'rejected');
    expect(repository.workspace.currentMemory!.id, before.currentMemory!.id);
  });

  test('接受选段提案逐字保留范围外内容并使旧记忆失效', () async {
    final original = repository.workspace.chapters.first.body;
    final start = original.indexOf('信纸');
    final end = original.indexOf('\n\n他没有');
    await run('proposeEdit', {
      'chapterId': 'chapter-1',
      'start': start,
      'end': end,
      'instruction': '改为不知道凶手',
    });
    await run('acceptProposal', {
      'proposalId': repository.workspace.proposals.single.id,
    });
    final after = repository.workspace;
    expect(
      after.chapters.first.body,
      '${original.substring(0, start)}替换后的选段。${original.substring(end)}',
    );
    expect(after.memoryFresh, isFalse);
    expect(after.chapters[1].needsReview, isTrue);
    expect(after.chapters[1].body, demoWorkspace().chapters[1].body);
  });

  test('按组合后的整章长度拒绝改稿，恰好达到上限的提案仍可接受', () async {
    final original = List.filled(100000, '甲').join();
    await run('saveChapter', {'chapterId': 'chapter-1', 'body': original});
    final before = repository.workspace;
    await expectLater(
      run('proposeEdit', {
        'chapterId': 'chapter-1',
        'start': 0,
        'end': 1,
        'instruction': '替换首字',
      }),
      throwsA(failure('invalid_output')),
    );
    expect(repository.workspace.toJson(), before.toJson());
    model.replacement = '乙';
    await run('proposeEdit', {
      'chapterId': 'chapter-1',
      'start': 0,
      'end': 1,
      'instruction': '只替换一字',
    });
    expect(repository.workspace.proposals.single.body.length, 100000);
    await run('acceptProposal', {
      'proposalId': repository.workspace.proposals.single.id,
    });
    expect(
      repository.workspace.chapters.first.body,
      '乙${original.substring(1)}',
    );
    expect(repository.workspace.proposals.single.status, 'accepted');
  });

  test('修改旧章、重建、续写、恢复旧稿的版本闭环', () async {
    await run('saveChapter', {'chapterId': 'chapter-1', 'body': '林舟还不知道凶手是谁。'});
    await expectLater(
      run('proposeChapter', {'instruction': '续写'}),
      throwsA(failure('memory_stale')),
    );
    await run('saveChapter', {
      'chapterId': 'chapter-2',
      'body': '林舟与阿岚调查来信，仍不知道凶手是谁。',
    });
    await run('rebuildMemory');
    expect(repository.workspace.memoryFresh, isTrue);
    expect(
      repository.workspace.currentMemory!.facts.every(
        (f) => f.evidence.contains('不知道凶手'),
      ),
      isTrue,
    );
    await run('proposeChapter', {'instruction': '调查来信'});
    final contextChapters = model.context!['acceptedChapters'] as List;
    expect(contextChapters[0]['body'], '林舟还不知道凶手是谁。');
    expect(contextChapters[1]['body'], '林舟与阿岚调查来信，仍不知道凶手是谁。');
    await run('rejectProposal', {
      'proposalId': repository.workspace.proposals.single.id,
    });
    await run('restoreVersion', {
      'chapterId': 'chapter-1',
      'versionId': 'seed-1',
    });
    expect(repository.workspace.memoryFresh, isFalse);
    await run('restoreVersion', {
      'chapterId': 'chapter-2',
      'versionId': 'seed-2',
    });
    expect(repository.workspace.memoryFresh, isTrue);
    expect(repository.workspace.currentMemory!.id, 'seed-memory');
    expect(
      repository.workspace.chapters.first.body,
      demoWorkspace().chapters.first.body,
    );
  });

  test('重建记忆不代替作者复查后续章节', () async {
    await run('saveChapter', {'chapterId': 'chapter-1', 'body': '林舟还不知道凶手是谁。'});
    await run('rebuildMemory');
    await expectLater(
      run('proposeChapter', {'instruction': '续写'}),
      throwsA(failure('review_required')),
    );
    await run('confirmReview', {'chapterId': 'chapter-2'});
    await run('proposeChapter', {'instruction': '续写'});
    expect(repository.workspace.proposals.single.status, 'pending');
  });

  test('过期提案和旧客户端不能覆盖新稿', () async {
    await run('proposeChapter', {'instruction': '续写'});
    final proposal = repository.workspace.proposals.single;
    final stale = command('rebuildMemory');
    await run('saveChapter', {'chapterId': 'chapter-1', 'body': '作者的新稿。'});
    await expectLater(
      run('acceptProposal', {'proposalId': proposal.id}),
      throwsA(failure('version_conflict')),
    );
    await expectLater(
      service.execute(stale),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.chapters.length, 2);
    expect(repository.workspace.chapters.first.body, '作者的新稿。');
  });

  test('改变作者资料也使旧提案不能接受', () async {
    await run('proposeChapter', {'instruction': '续写'});
    final proposal = repository.workspace.proposals.single;
    await run('saveDocument', {
      'id': 'setting-1',
      'title': '新设定',
      'kind': 'setting',
      'body': '改用第一人称。',
    });
    await expectLater(
      run('acceptProposal', {'proposalId': proposal.id}),
      throwsA(failure('version_conflict')),
    );
  });

  test('生成期间允许作者保存，返回后发现冲突而不应用结果', () async {
    model.gate = Completer<ModelDraft>();
    final generating = run('proposeChapter', {'instruction': '续写'});
    await model.started.future;
    await run('saveChapter', {
      'chapterId': 'chapter-1',
      'body': '生成期间作者修改的正文。',
    });
    model.gate!.complete(const ModelDraft('标题', '迟到的草稿。'));
    await expectLater(generating, throwsA(failure('version_conflict')));
    expect(repository.workspace.proposals, isEmpty);
    expect(repository.workspace.chapters.first.body, '生成期间作者修改的正文。');
  });

  test('错误记忆证据不会写入工作区', () async {
    await run('saveChapter', {'chapterId': 'chapter-1', 'body': '新正文。'});
    final revision = repository.workspace.revision;
    model.badEvidence = true;
    await expectLater(run('rebuildMemory'), throwsA(failure('invalid_memory')));
    expect(repository.workspace.revision, revision);
    expect(repository.workspace.memoryFresh, isFalse);
  });

  test('记忆上限按每章检查，不以总量掩盖单章过量', () async {
    model.tooManyFacts = true;
    await expectLater(run('rebuildMemory'), throwsA(failure('invalid_memory')));
    expect(repository.workspace.revision, 0);
    expect(repository.workspace.currentMemory!.id, 'seed-memory');
  });

  test('模型失败不提交回执，相同请求可以重新生成', () async {
    model.gate = Completer<ModelDraft>();
    final request = command('proposeChapter', {'instruction': '续写'});
    final failing = service.execute(request);
    await model.started.future;
    model.gate!.completeError(StateError('测试中的供应商故障'));
    await expectLater(failing, throwsA(failure('model_failed')));
    expect(repository.workspace.revision, 0);
    expect(repository.workspace.receipts, isEmpty);
    model.gate = null;
    await service.execute(request);
    expect(repository.workspace.revision, 1);
    expect(repository.workspace.proposals, hasLength(1));
    expect(model.calls, 2);
  });

  test('并发同请求共享结果，重试不重复生成或提交', () async {
    model.gate = Completer<ModelDraft>();
    final request = command('proposeChapter', {'instruction': '续写'});
    final first = service.execute(request);
    final duplicate = service.execute(request);
    await model.started.future;
    model.gate!.complete(const ModelDraft('标题', '正文。'));
    await Future.wait([first, duplicate]);
    final result = await service.execute(request);
    expect(result['reused'], isTrue);
    expect(model.calls, 1);
    expect(repository.workspace.proposals.length, 1);
    expect(repository.workspace.revision, 1);
    await expectLater(
      service.execute(
        NovelCommand(
          requestId: request.requestId,
          expectedRevision: request.expectedRevision,
          operation: 'rebuildMemory',
          payload: {},
        ),
      ),
      throwsA(failure('request_conflict')),
    );
  });

  test('冷启动后重试已接受操作也不重复应用', () async {
    final directory = await Directory.systemTemp.createTemp('novel-test-');
    addTearDown(() => directory.delete(recursive: true));
    final fileRepository = await FileWorkspaceRepository.open(
      '${directory.path}/store.json',
    );
    var fileService = NovelService(fileRepository, model);
    final request = NovelCommand(
      requestId: 'persistent-save',
      expectedRevision: 0,
      operation: 'saveChapter',
      payload: {'chapterId': 'chapter-1', 'body': '冷启动保留的正文。'},
    );
    await fileService.execute(request);
    fileService = NovelService(
      await FileWorkspaceRepository.open('${directory.path}/store.json'),
      model,
    );
    expect((await fileService.execute(request))['reused'], isTrue);
    final loaded = await fileRepository.load();
    expect(loaded.chapters.first.versions.length, 2);
    expect(loaded.revision, 1);
  });
}

class RecordingModel implements NovelModel {
  Json? context;
  Completer<ModelDraft>? gate;
  final started = Completer<void>();
  bool badEvidence = false;
  bool tooManyFacts = false;
  int calls = 0;
  String replacement = '替换后的选段。';
  @override
  String get name => 'test/model';
  @override
  Future<ModelDraft> write(
    Json context,
    String instruction, {
    bool edit = false,
  }) async {
    calls++;
    this.context = context;
    if (!started.isCompleted) started.complete();
    if (gate != null) return gate!.future;
    return ModelDraft('下一章', edit ? replacement : '新章正文。');
  }

  @override
  Future<List<StoryFact>> extract(Workspace workspace) async => [
    for (final c in workspace.chapters)
      for (var i = 0; i < (tooManyFacts && c.number == 1 ? 9 : 1); i++)
        StoryFact(
          text: '原文事实',
          chapterId: c.id,
          versionId: c.head,
          evidence: badEvidence ? '不存在的证据' : c.body.split('\n').first,
        ),
  ];
}
