import 'dart:async';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';

Matcher failure(String code) =>
    isA<LibraryFailure>().having((e) => e.code, 'code', code);

class WorkModel implements NovelModel {
  final List<Json> contexts = [];
  Completer<void>? started;
  Completer<void>? release;
  bool fail = false;
  @override
  String get name => 'test/work-model';
  @override
  Future<ModelDraft> write(
    Json context,
    String instruction, {
    bool edit = false,
  }) async {
    contexts.add(context);
    started?.complete();
    if (release != null) await release!.future;
    if (fail) throw StateError('模拟模型失败');
    return ModelDraft('$instruction 章', edit ? '替换片段' : '开头 $instruction 结尾');
  }

  @override
  Future<List<StoryFact>> extract(Workspace workspace) async => [
    for (final c in workspace.chapters)
      StoryFact(
        text: c.body,
        chapterId: c.id,
        versionId: c.head,
        evidence: c.body,
      ),
  ];
}

void main() {
  late InMemoryLibraryRepository repository;
  late LibraryService service;
  late WorkModel model;
  var sequence = 0;
  setUp(() {
    sequence = 0;
    repository = InMemoryLibraryRepository();
    model = WorkModel();
    service = LibraryService(repository, model: model);
  });
  Future<Json> act(
    String id,
    String operation, [
    Json payload = const {},
  ]) async => service.execute(
    command(
      'body-${++sequence}',
      (await repository.load()).revision,
      operation,
      payload,
      target: CommandTarget.work(id),
    ),
  );
  Future<void> seed() async {
    await service.execute(createWork());
    await service.execute(createWork(1, 'work-b'));
  }

  Future<void> chapter(String workId, String instruction) async {
    await act(workId, 'proposeChapter', {'instruction': instruction});
    final proposal = (await repository.load())
        .work(workId)
        .proposals
        .last
        .proposal;
    await act(workId, 'acceptProposal', {'proposalId': proposal.id});
    await act(workId, 'rebuildMemory');
  }

  test('无模型创建空白章节、保存正文与重试，章节顺序和其他作品保持独立', () async {
    await seed();
    service = LibraryService(repository);
    final original = command('manual-first', 2, 'createChapter', {
      'chapterId': 'chapter-2',
      'title': '作者的开篇',
    }, target: CommandTarget.work('work-a'));
    await service.execute(original);
    final created = repository.workspace.work('work-a').chapters.single;
    expect(created.number, 1);
    expect(created.title, '作者的开篇');
    expect(created.body, isEmpty);
    expect(created.versions.length, 1);
    expect(repository.workspace.work('work-a').proposals, isEmpty);
    final loaded = LibraryWorkspace.fromJson(repository.workspace.toJson());
    expect(loaded.work('work-a').chapters.single.body, isEmpty);
    await act('work-b', 'createChapter', {
      'chapterId': 'chapter-2',
      'title': 'B 的开篇',
    });
    expect((await service.execute(original))['reused'], isTrue);
    expect(repository.workspace.work('work-a').chapters.length, 1);
    await act('work-a', 'saveChapter', {
      'chapterId': 'chapter-2',
      'body': '作者亲自写下的正文。',
    });
    expect(
      repository.workspace.work('work-a').chapters.single.versions.length,
      2,
    );
    expect(repository.workspace.work('work-b').chapters.single.body, isEmpty);
    await expectLater(
      act('work-a', 'createChapter', {
        'chapterId': 'chapter-2',
        'title': '不覆盖已有章节',
      }),
      throwsA(failure('chapter_exists')),
    );
    service = LibraryService(repository, model: model);
    await act('work-a', 'rebuildMemory');
    await act('work-a', 'proposeChapter', {'instruction': '下一章'});
    final proposal = repository.workspace
        .work('work-a')
        .proposals
        .single
        .proposal;
    expect(proposal.chapterId, isNot('chapter-2'));
    await act('work-a', 'acceptProposal', {'proposalId': proposal.id});
    expect(repository.workspace.work('work-a').chapters.map((c) => c.number), [
      1,
      2,
    ]);
    expect(repository.workspace.work('work-a').chapters.first.title, '作者的开篇');
  });

  test('空白章节不能产生故事记忆或被跳过续写，旧修订号不能新建章节', () async {
    await seed();
    await act('work-a', 'createChapter', {
      'chapterId': 'blank',
      'title': '等待作者写作',
    });
    final before = repository.workspace.toJson();
    await expectLater(
      act('work-a', 'rebuildMemory'),
      throwsA(failure('chapter_empty')),
    );
    await expectLater(
      act('work-a', 'proposeChapter', {'instruction': '跳过空章'}),
      throwsA(failure('chapter_empty')),
    );
    await expectLater(
      service.execute(
        command('stale-create', 2, 'createChapter', {
          'chapterId': 'another',
          'title': '不应创建',
        }, target: CommandTarget.work('work-a')),
      ),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.toJson(), before);
    expect(model.contexts, isEmpty);
  });

  test('两作品正文、历史、提案与记忆独立；命名、旧章修改、复查和恢复只影响目标', () async {
    await seed();
    await chapter('work-a', 'A1');
    await chapter('work-a', 'A2');
    await chapter('work-b', 'B1');
    final base = await repository.load();
    final a = base.work('work-a');
    final b = base.work('work-b').toJson();
    final originalHead = a.chapters.first.head;
    expect(a.chapters.first.id, base.work('work-b').chapters.first.id);
    expect(model.contexts.last['workId'], 'work-b');
    expect(model.contexts.last['acceptedChapters'], isEmpty);
    await act('work-a', 'renameWork', {'title': '  作品 A 新名  '});
    await act('work-a', 'saveChapter', {
      'chapterId': 'chapter-1',
      'body': '作者修改 A1',
    });
    var state = await repository.load();
    expect(state.work('work-a').title, '  作品 A 新名  ');
    expect(state.work('work-b').toJson(), b);
    expect(state.work('work-a').chapters.first.versions.length, 2);
    expect(state.work('work-a').chapters[1].needsReview, isTrue);
    expect(state.workView('work-a').memoryFresh, isFalse);
    await expectLater(
      act('work-a', 'proposeChapter', {'instruction': 'A3'}),
      throwsA(failure('memory_stale')),
    );
    await act('work-a', 'rebuildMemory');
    await expectLater(
      act('work-a', 'proposeChapter', {'instruction': 'A3'}),
      throwsA(failure('review_required')),
    );
    await act('work-a', 'confirmReview', {'chapterId': 'chapter-2'});
    await act('work-a', 'restoreVersion', {
      'chapterId': 'chapter-1',
      'versionId': originalHead,
    });
    state = await repository.load();
    expect(state.workView('work-a').memoryFresh, isTrue);
    expect(state.work('work-a').chapters[1].needsReview, isTrue);
    expect(state.work('work-b').toJson(), b);
    expect(
      state.receipts.values
          .where((r) => r.target.kind == 'work')
          .every((r) => {'work-a', 'work-b'}.contains(r.target.workId)),
      isTrue,
    );
  });

  test('拒绝不改正文；改稿保留选段外文本；跨作品提案和旧来源接受被拒绝', () async {
    await seed();
    await chapter('work-a', 'A1');
    await chapter('work-b', 'B1');
    final before = await repository.load();
    final body = before.work('work-a').chapters.first.body;
    await act('work-a', 'proposeEdit', {
      'chapterId': 'chapter-1',
      'start': 3,
      'end': 5,
      'instruction': '改稿',
    });
    final edit = (await repository.load())
        .work('work-a')
        .proposals
        .last
        .proposal;
    expect(edit.body, '${body.substring(0, 3)}替换片段${body.substring(5)}');
    await expectLater(
      act('work-b', 'acceptProposal', {'proposalId': edit.id}),
      throwsA(failure('proposal_unavailable')),
    );
    await act('work-a', 'rejectProposal', {'proposalId': edit.id});
    expect((await repository.load()).work('work-a').chapters.first.body, body);
    await act('work-a', 'proposeEdit', {
      'chapterId': 'chapter-1',
      'start': 3,
      'end': 5,
      'instruction': '改稿',
    });
    final accepted = (await repository.load())
        .work('work-a')
        .proposals
        .last
        .proposal;
    await act('work-a', 'acceptProposal', {'proposalId': accepted.id});
    expect(
      (await repository.load()).work('work-a').chapters.first.body,
      accepted.body,
    );
    await act('work-a', 'proposeEdit', {
      'chapterId': 'chapter-1',
      'start': 3,
      'end': 5,
      'instruction': '新改稿',
    });
    final stale = (await repository.load())
        .work('work-a')
        .proposals
        .last
        .proposal;
    await act('work-a', 'saveChapter', {
      'chapterId': 'chapter-1',
      'body': '更新正文',
    });
    await expectLater(
      act('work-a', 'acceptProposal', {'proposalId': stale.id}),
      throwsA(failure('version_conflict')),
    );
    expect(
      (await repository.load()).work('work-b').toJson(),
      before.work('work-b').toJson(),
    );
  });

  test('无模型仍能保存、命名、复查与恢复；已提交同请求重试只追加一次版本', () async {
    await seed();
    await chapter('work-a', 'A1');
    service = LibraryService(repository);
    final original = command(
      'save-once',
      repository.workspace.revision,
      'saveChapter',
      {'chapterId': 'chapter-1', 'body': '无模型保存'},
      target: CommandTarget.work('work-a'),
    );
    await service.execute(original);
    final after = repository.workspace;
    await act('work-b', 'renameWork', {'title': 'B 新名'});
    expect((await service.execute(original))['reused'], isTrue);
    expect(
      repository.workspace.work('work-a').toJson(),
      after.work('work-a').toJson(),
    );
    await act('work-a', 'restoreVersion', {
      'chapterId': 'chapter-1',
      'versionId': after.work('work-a').chapters.first.versions.first.id,
    });
    await act('work-a', 'confirmReview', {'chapterId': 'chapter-1'});
    await expectLater(
      act('work-b', 'proposeChapter', {'instruction': 'B1'}),
      throwsA(failure('model_unavailable')),
    );
  });

  test('生成时同请求合并，目标不同立即冲突；其他作品提交后拒绝迟到结果', () async {
    await seed();
    await chapter('work-b', 'B1');
    model.started = Completer();
    model.release = Completer();
    final generate = command(
      'in-flight',
      repository.workspace.revision,
      'proposeChapter',
      {'instruction': 'A1'},
      target: CommandTarget.work('work-a'),
    );
    final waiting = service.execute(generate);
    final repeated = service.execute(generate);
    final failed = expectLater(waiting, throwsA(failure('version_conflict')));
    final failedRepeat = expectLater(
      repeated,
      throwsA(failure('version_conflict')),
    );
    await model.started!.future;
    await expectLater(
      service.execute(
        command(
          'in-flight',
          repository.workspace.revision,
          'renameWork',
          {'title': 'B 误写'},
          target: CommandTarget.work('work-b'),
        ),
      ),
      throwsA(failure('request_conflict')),
    );
    await act('work-b', 'saveChapter', {
      'chapterId': 'chapter-1',
      'body': 'B 新正文',
    });
    model.release!.complete();
    await Future.wait([failed, failedRepeat]);
    expect(model.contexts.where((c) => c['workId'] == 'work-a').length, 1);
    expect(repository.workspace.work('work-a').proposals, isEmpty);
    expect(repository.workspace.work('work-b').chapters.first.body, 'B 新正文');
    expect(repository.workspace.receipts.containsKey('in-flight'), isFalse);
  });

  test('模型失败不污染其他作品，可重新执行未提交请求；成功回执跨服务重试复用', () async {
    await seed();
    model.fail = true;
    final generate = command('retry-generation', 2, 'proposeChapter', {
      'instruction': 'A1',
    }, target: CommandTarget.work('work-a'));
    await expectLater(
      service.execute(generate),
      throwsA(failure('model_failed')),
    );
    expect(repository.workspace.revision, 2);
    model.fail = false;
    await service.execute(generate);
    final saved = repository.workspace.toJson();
    service = LibraryService(repository);
    expect((await service.execute(generate))['reused'], isTrue);
    expect(repository.workspace.toJson(), saved);
    expect(repository.workspace.work('work-b').proposals, isEmpty);
  });

  test('上下文只包含目标作品采用的资料版本；来源换版后即使正文相同也拒绝接受', () async {
    await seed();
    await service.execute(createLibrary(2));
    await service.execute(saveDocument(3, body: '共有设定'));
    await service.execute(
      saveDocument(
        4,
        requestId: 'doc-v2',
        versionId: 'v2',
        previous: 'v1',
        body: '共有设定',
      ),
    );
    Future<void> pin(String version) async {
      final base = repository.workspace;
      final work = base.work('work-a');
      final replacement = NovelWork(
        id: work.id,
        title: work.title,
        knowledgeLinks: [
          LibraryLink(libraryId: 'library-a', versions: {'doc-a': version}),
        ],
        chapters: work.chapters,
        proposals: work.proposals,
        memories: work.memories,
        discussions: work.discussions,
      );
      // M4's adoption service is not implemented yet. Seed a valid committed
      // pin change to verify M3's existing source-version acceptance boundary.
      await repository.save(
        LibraryWorkspace(
          revision: base.revision + 1,
          works: [replacement, base.work('work-b')],
          libraries: base.libraries,
          receipts: base.receipts,
        ),
        base.revision,
      );
    }

    await pin('v1');
    await act('work-a', 'proposeChapter', {'instruction': 'A1'});
    final proposed = repository.workspace.work('work-a').proposals.single;
    expect(proposed.documents.single.versionId, 'v1');
    expect(model.contexts.last['basis']['documents'][0]['versionId'], 'v1');
    expect((model.contexts.last['documents'] as List).single['body'], '共有设定');
    await act('work-b', 'proposeChapter', {'instruction': 'B1'});
    expect(model.contexts.last['documents'], isEmpty);
    await pin('v2');
    await expectLater(
      act('work-a', 'acceptProposal', {'proposalId': proposed.proposal.id}),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.work('work-a').chapters, isEmpty);
    expect(
      repository.workspace
          .work('work-a')
          .proposals
          .single
          .documents
          .single
          .versionId,
      'v1',
    );
  });
}
