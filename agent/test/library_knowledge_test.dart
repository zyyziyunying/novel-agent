import 'dart:async';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';

class KnowledgeModel implements NovelModel {
  final List<Json> contexts = [];
  Completer<void>? started;
  Completer<void>? release;
  @override
  String get name => 'test/knowledge';
  @override
  Future<ModelDraft> write(
    Json context,
    String instruction, {
    bool edit = false,
  }) async {
    contexts.add(context);
    started?.complete();
    if (release != null) await release!.future;
    return ModelDraft('第一章', '作者接受后才成为故事事实。');
  }

  @override
  Future<List<StoryFact>> extract(Workspace workspace) async => [
    for (final chapter in workspace.chapters)
      StoryFact(
        text: chapter.body,
        chapterId: chapter.id,
        versionId: chapter.head,
        evidence: chapter.body,
      ),
  ];
}

void main() {
  late InMemoryLibraryRepository repository;
  late LibraryService service;
  late KnowledgeModel model;
  var sequence = 0;
  setUp(() {
    sequence = 0;
    repository = InMemoryLibraryRepository();
    model = KnowledgeModel();
    service = LibraryService(repository, model: model);
  });
  Future<Json> act(String workId, String operation, Json payload) async =>
      service.execute(
        command(
          'knowledge-${++sequence}',
          repository.workspace.revision,
          operation,
          payload,
          target: CommandTarget.work(workId),
        ),
      );
  Future<Json> links(String workId, List<LibraryLink> value) => act(
    workId,
    'setKnowledgeLinks',
    {'links': value.map((l) => l.toJson()).toList()},
  );
  LibraryLink pin(String libraryId, String version) =>
      LibraryLink(libraryId: libraryId, versions: {'doc-a': version});
  Future<void> seed() async {
    for (final id in ['work-a', 'work-b', 'work-c']) {
      await service.execute(createWork(repository.workspace.revision, id));
    }
    for (final id in ['library-a', 'library-b']) {
      await service.execute(createLibrary(repository.workspace.revision, id));
      await service.execute(
        saveDocument(
          repository.workspace.revision,
          requestId: 'save-$id-v1',
          libraryId: id,
          workId: null,
          body: '$id 原始参考',
        ),
      );
    }
    await links('work-a', [pin('library-a', 'v1'), pin('library-b', 'v1')]);
    await links('work-b', [pin('library-a', 'v1')]);
  }

  Matcher failure(String code) =>
      isA<LibraryFailure>().having((e) => e.code, 'code', code);

  test('A 采用两个库、B 采用共享库、C 未关联，模型仅获得各作品固定版本与完整来源', () async {
    await seed();
    for (final id in ['work-a', 'work-b', 'work-c']) {
      await act(id, 'proposeChapter', {'instruction': '写开篇'});
    }
    expect(model.contexts.map((c) => (c['documents'] as List).length), [
      2,
      1,
      0,
    ]);
    expect(model.contexts[0]['documents'][0]['body'], 'library-a 原始参考');
    final manifest = model.contexts[0]['knowledgeDocuments'][0];
    expect(manifest['libraryId'], 'library-a');
    expect(manifest['documentId'], 'doc-a');
    expect(manifest['versionId'], 'v1');
    expect(manifest['version']['provenance']['writer']['id'], 'Codex');
    expect(
      manifest['version']['provenance']['sources'][0]['reference'],
      'https://example.com/story',
    );
    expect(
      repository.workspace.work('work-a').proposals.single.documents.length,
      2,
    );
    expect(
      repository.workspace.work('work-c').proposals.single.documents,
      isEmpty,
    );
    expect(
      repository.workspace.works.every(
        (w) => w.chapters.isEmpty && w.memories.isEmpty,
      ),
      isTrue,
    );
  });

  test('库发布新版不改变采用、记忆和历史提案，作者单独采用后旧提案冲突', () async {
    await seed();
    await act('work-a', 'proposeChapter', {'instruction': '按旧版起草'});
    final historical = repository.workspace.work('work-a').proposals.single;
    await service.execute(
      saveDocument(
        repository.workspace.revision,
        requestId: 'publish-v2',
        versionId: 'v2',
        previous: 'v1',
        workId: null,
        body: '新参考',
      ),
    );
    expect(repository.workspace.isBasisCurrent(historical.basis), isTrue);
    expect(
      repository.workspace.workView('work-b').documents.single.body,
      'library-a 原始参考',
    );
    await links('work-a', [pin('library-a', 'v2'), pin('library-b', 'v1')]);
    expect(repository.workspace.isBasisCurrent(historical.basis), isFalse);
    await expectLater(
      act('work-a', 'acceptProposal', {'proposalId': historical.proposal.id}),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.work('work-a').chapters, isEmpty);
    expect(
      repository.workspace
          .work('work-a')
          .proposals
          .single
          .proposal
          .context['knowledgeDocuments'][0]['versionId'],
      'v1',
    );
    expect(
      repository.workspace.documentVersion(historical.documents.first).body,
      'library-a 原始参考',
    );
    await act('work-a', 'proposeChapter', {'instruction': '按新版本起草'});
    expect(model.contexts.last['knowledgeDocuments'][0]['versionId'], 'v2');
    expect(model.contexts.last['documents'][0]['body'], '新参考');
    // Each work controls adoption independently; B can accept its own old pins.
    await act('work-b', 'proposeChapter', {'instruction': 'B 沿用旧版'});
    await act('work-b', 'acceptProposal', {
      'proposalId': repository.workspace
          .work('work-b')
          .proposals
          .single
          .proposal
          .id,
    });
    await act('work-b', 'rebuildMemory', {});
    final memory = repository.workspace.work('work-b').memories.single.toJson();
    await links('work-b', [pin('library-a', 'v2')]);
    expect(
      repository.workspace.work('work-b').memories.single.toJson(),
      memory,
    );
    expect(repository.workspace.workView('work-b').memoryFresh, isTrue);
  });

  test('只发布共享新版或重排同一采用清单，历史提案仍可接受', () async {
    await seed();
    await act('work-a', 'proposeChapter', {'instruction': '基于 v1'});
    final proposal = repository.workspace.work('work-a').proposals.single;
    await service.execute(
      saveDocument(
        repository.workspace.revision,
        requestId: 'publish-only',
        versionId: 'v2',
        previous: 'v1',
        workId: null,
      ),
    );
    await links('work-a', [pin('library-b', 'v1'), pin('library-a', 'v1')]);
    expect(repository.workspace.isBasisCurrent(proposal.basis), isTrue);
    await act('work-a', 'acceptProposal', {'proposalId': proposal.proposal.id});
    expect(
      repository.workspace.work('work-a').chapters.single.body,
      proposal.proposal.body,
    );
    expect(
      repository.workspace
          .work('work-a')
          .proposals
          .single
          .documents
          .map((r) => r.versionId),
      ['v1', 'v1'],
    );
  });

  test('未知库、资料或版本、旧修订及重复请求冲突均不覆盖采用', () async {
    await seed();
    final before = repository.workspace.toJson();
    for (final invalid in [
      LibraryLink(libraryId: 'missing', versions: {}),
      LibraryLink(libraryId: 'library-a', versions: {'missing': 'v1'}),
      pin('library-a', 'missing'),
    ]) {
      await expectLater(
        links('work-a', [invalid]),
        throwsA(failure('invalid_reference')),
      );
      expect(repository.workspace.toJson(), before);
    }
    final original = command(
      'stable-links',
      repository.workspace.revision,
      'setKnowledgeLinks',
      {'links': []},
      target: CommandTarget.work('work-a'),
    );
    await service.execute(original);
    expect((await service.execute(original))['reused'], isTrue);
    await expectLater(
      service.execute(
        command(
          'stable-links',
          repository.workspace.revision,
          'setKnowledgeLinks',
          {
            'links': [pin('library-a', 'v1').toJson()],
          },
          target: CommandTarget.work('work-a'),
        ),
      ),
      throwsA(failure('request_conflict')),
    );
    await expectLater(
      service.execute(
        command('stale-links', 0, 'setKnowledgeLinks', {
          'links': [],
        }, target: CommandTarget.work('work-b')),
      ),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.work('work-a').knowledgeLinks, isEmpty);
    expect(
      repository.workspace.work('work-b').adoptedDocuments.single.versionId,
      'v1',
    );
  });

  for (final publishOnly in [true, false]) {
    test('在途生成遇到${publishOnly ? '共享库发布' : '作品采用变更'}后保守拒绝迟到结果', () async {
      await seed();
      model.started = Completer<void>();
      model.release = Completer<void>();
      final generating = act('work-a', 'proposeChapter', {'instruction': '等待'});
      final rejected = expectLater(
        generating,
        throwsA(failure('version_conflict')),
      );
      await model.started!.future;
      if (publishOnly) {
        await service.execute(
          saveDocument(
            repository.workspace.revision,
            requestId: 'during-v2',
            versionId: 'v2',
            previous: 'v1',
            workId: null,
          ),
        );
      } else {
        await links('work-a', []);
      }
      model.release!.complete();
      await rejected;
      expect(repository.workspace.work('work-a').proposals, isEmpty);
      expect(
        repository.workspace.receipts.values.where(
          (r) => r.revision > repository.workspace.revision,
        ),
        isEmpty,
      );
    });
  }
}
