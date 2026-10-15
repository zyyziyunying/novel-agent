import 'dart:async';
import 'dart:convert';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

class SelectingModel extends FixtureNovelModel {
  final directories = <Json>[];
  final contexts = <Json>[];
  List<String>? keys;
  bool failSelection = false;
  bool failReply = false;
  Completer<void>? selected;
  Completer<void>? selectionRelease;
  Completer<void>? replying;
  Completer<void>? replyRelease;

  @override
  Future<KnowledgeSelection> selectKnowledge(
    Json directory,
    String instruction,
  ) async {
    directories.add(directory);
    selected?.complete();
    if (selectionRelease != null) await selectionRelease!.future;
    if (failSelection) throw StateError('selection failed');
    return KnowledgeSelection(
      keys ?? [knowledgeKey(ref('hit'))],
      usage: {'inputTokens': 12},
    );
  }

  @override
  Future<ModelDraft> write(
    Json context,
    String instruction, {
    bool edit = false,
  }) async {
    contexts.add(context);
    return ModelDraft('起草结果', '只有作者接受后才能成为正文。');
  }

  @override
  Future<String> discuss(Json context, String instruction) async {
    contexts.add(context);
    replying?.complete();
    if (replyRelease != null) await replyRelease!.future;
    if (failReply) throw StateError('reply failed');
    return '资料核对后的建议';
  }
}

DocumentReference ref(String id) =>
    DocumentReference(libraryId: 'lib', documentId: id, versionId: 'v1');

LibraryWorkspace seed() {
  KnowledgeVersion version(String id, {String versionId = 'v1'}) =>
      KnowledgeVersion(
        id: versionId,
        title: id,
        kind: id == 'core' ? 'setting' : 'reference',
        body: 'FULLTEXT-$id-$versionId',
        description: id == 'legacy' ? '' : 'DESCRIPTION-$id-$versionId',
        tags: ['tag-$id'],
        alwaysRead: id == 'core',
        associatedWorkId: null,
        provenance: SourceProvenance(
          writer: SourceWriter(kind: 'author', id: 'author'),
          sources: [ExternalSource(kind: 'author', reference: '作者原始输入')],
        ),
      );
  return LibraryWorkspace(
    revision: 0,
    works: [
      NovelWork(
        id: 'work',
        title: '作品',
        knowledgeLinks: [
          LibraryLink(
            libraryId: 'lib',
            versions: {
              for (final id in ['core', 'hit', 'other', 'legacy']) id: 'v1',
            },
          ),
        ],
        chapters: [],
        proposals: [],
        memories: [],
        discussions: [
          Discussion(
            id: 'talk',
            title: '讨论',
            chapterId: null,
            messages: [],
            turns: [],
          ),
        ],
      ),
    ],
    libraries: [
      KnowledgeLibrary(
        id: 'lib',
        name: '资料库',
        documents: [
          for (final id in ['core', 'hit', 'other', 'legacy', 'unadopted'])
            KnowledgeDocument(
              id: id,
              head: id == 'hit' ? 'v2' : 'v1',
              versions: [
                version(id),
                if (id == 'hit') version(id, versionId: 'v2'),
              ],
            ),
        ],
      ),
    ],
    receipts: {},
  );
}

void main() {
  late InMemoryLibraryRepository repository;
  late LibraryService service;
  late SelectingModel model;
  var sequence = 0;
  setUp(() {
    repository = InMemoryLibraryRepository(seed());
    model = SelectingModel();
    service = LibraryService(repository, model: model);
    sequence = 0;
  });
  LibraryCommand command(
    String operation,
    Json payload, {
    bool discussion = false,
  }) => LibraryCommand(
    requestId: 'request-${++sequence}',
    expectedRevision: repository.workspace.revision,
    target: discussion
        ? CommandTarget.discussion(workId: 'work', discussionId: 'talk')
        : CommandTarget.work('work'),
    operation: operation,
    payload: payload,
  );
  LibraryCommand send() => command('sendDiscussionMessage', {
    'messageId': 'message-${sequence + 1}',
    'body': '讨论影子',
  }, discussion: true);
  Matcher failure(String code) =>
      isA<LibraryFailure>().having((e) => e.code, 'code', code);

  test('先只看目录，正文只加载命中、必读和旧资料，固定旧版且不自动接受', () async {
    await service.execute(command('proposeChapter', {'instruction': '写开篇'}));
    final directory = jsonEncode(model.directories.single);
    expect(directory, isNot(contains('FULLTEXT')));
    expect(directory, isNot(contains('unadopted')));
    expect(directory, contains('DESCRIPTION-hit-v1'));
    expect(directory, isNot(contains('DESCRIPTION-hit-v2')));
    final context = model.contexts.single;
    expect(
      (context['readDocuments'] as List).map((e) => e['documentId']).toSet(),
      {'core', 'hit', 'legacy'},
    );
    expect(jsonEncode(context), isNot(contains('FULLTEXT-other')));
    expect(jsonEncode(context), isNot(contains('FULLTEXT-hit-v2')));
    expect(jsonEncode(context), contains('FULLTEXT-core-v1'));
    final proposal = repository.workspace
        .work('work')
        .proposals
        .single
        .proposal;
    expect(proposal.context, context);
    expect(proposal.usage['knowledgeSelection'], {'inputTokens': 12});
    expect(repository.workspace.work('work').chapters, isEmpty);
    await service.execute(
      command('acceptProposal', {'proposalId': proposal.id}),
    );
    expect(
      repository.workspace.work('work').chapters.single.body,
      proposal.body,
    );
  });

  test('模型可不选任何可选资料，必读仍强制加载', () async {
    model.keys = [];
    await service.execute(send());
    expect(
      (model.contexts.single['readDocuments'] as List)
          .map((e) => e['documentId'])
          .toSet(),
      {'core', 'legacy'},
    );
  });

  test('拒绝目录外和重复选择，选择失败不提交提案或继续读全文', () async {
    for (final keys in [
      [knowledgeKey(ref('unadopted'))],
      [knowledgeKey(ref('hit')), knowledgeKey(ref('hit'))],
    ]) {
      model.keys = keys;
      await expectLater(
        service.execute(command('proposeChapter', {'instruction': '起草'})),
        throwsA(failure('model_failed')),
      );
    }
    model.failSelection = true;
    await service.execute(send());
    expect(
      repository.workspace
          .work('work')
          .discussions
          .single
          .turns
          .single
          .errorCode,
      'model_failed',
    );
    expect(model.contexts, isEmpty);
    expect(repository.workspace.work('work').proposals, isEmpty);
  });

  test('讨论选择先持久化，模型失败与重启后的原请求重试复用清单和上下文', () async {
    model.failReply = true;
    final request = send();
    await service.execute(request);
    final original = model.contexts.single;
    final saved = LibraryWorkspace.fromJson(repository.workspace.toJson());
    expect(
      saved.work('work').discussions.single.turns.single.readDocuments,
      hasLength(3),
    );
    repository = InMemoryLibraryRepository(saved);
    service = LibraryService(repository, model: model);
    model.failReply = false;
    model.keys = [];
    await service.execute(request);
    expect(model.directories, hasLength(1));
    expect(model.contexts.last, original);
    await service.execute(request);
    expect(model.contexts, hasLength(2));
    expect(
      repository.workspace.work('work').discussions.single.messages,
      hasLength(2),
    );
  });

  test('选择期间采用来源变化时拒绝迟到结果，原已保存资料保留', () async {
    model.selected = Completer<void>();
    model.selectionRelease = Completer<void>();
    final operation = service.execute(send());
    await model.selected!.future;
    await service.execute(command('setKnowledgeLinks', {'links': []}));
    model.selectionRelease!.complete();
    await operation;
    expect(
      repository.workspace
          .work('work')
          .discussions
          .single
          .turns
          .single
          .errorCode,
      'version_conflict',
    );
    expect(model.contexts, isEmpty);
    expect(repository.workspace.libraries.single.documents, hasLength(5));
  });

  test('选择后的 pending 中断恢复保留读取版本，重试不重新选择', () async {
    model.replying = Completer<void>();
    model.replyRelease = Completer<void>();
    final request = send();
    final operation = service.execute(request);
    await model.replying!.future;
    final snapshot = LibraryWorkspace.fromJson(repository.workspace.toJson());
    expect(
      snapshot.work('work').discussions.single.turns.single.readDocuments,
      hasLength(3),
    );
    final recovered = InMemoryLibraryRepository(snapshot);
    final retryModel = SelectingModel()..keys = [];
    final restarted = LibraryService(recovered, model: retryModel);
    await restarted.initialize();
    expect(
      recovered.workspace
          .work('work')
          .discussions
          .single
          .turns
          .single
          .errorCode,
      'interrupted',
    );
    await restarted.execute(request);
    expect(retryModel.directories, isEmpty);
    expect(retryModel.contexts.single, model.contexts.single);
    model.replyRelease!.complete();
    await operation;
  });
}
