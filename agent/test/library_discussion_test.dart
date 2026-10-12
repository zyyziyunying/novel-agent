import 'dart:async';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';

class DiscussionTestModel extends FixtureNovelModel {
  final List<Json> contexts = [];
  bool fail = false;
  String? output;
  Completer<void>? started;
  Completer<void>? release;
  @override
  Future<String> discuss(Json context, String instruction) async {
    contexts.add(context);
    started?.complete();
    if (release != null) await release!.future;
    if (fail) throw StateError('供应商私有错误与密钥不能进入记录');
    return output ?? '建议：$instruction';
  }
}

Matcher failure(String code) =>
    isA<LibraryFailure>().having((f) => f.code, 'code', code);

void main() {
  late InMemoryLibraryRepository repository;
  late LibraryService service;
  late DiscussionTestModel model;
  var sequence = 0;
  setUp(() async {
    sequence = 0;
    final demo = demoWorkspace();
    NovelWork work(String id) => NovelWork(
      id: id,
      title: id,
      knowledgeLinks: [],
      chapters: demo.chapters,
      proposals: [],
      memories: demo.memories,
      discussions: [],
    );
    repository = InMemoryLibraryRepository(
      LibraryWorkspace(
        revision: 0,
        works: [work('a'), work('b')],
        libraries: [],
        receipts: {},
      ),
    );
    model = DiscussionTestModel();
    service = LibraryService(repository, model: model);
  });
  Future<Json> act(String operation, Json payload, {CommandTarget? target}) =>
      service.execute(
        command(
          'm5-${++sequence}',
          repository.workspace.revision,
          operation,
          payload,
          target: target ?? CommandTarget.work('a'),
        ),
      );
  Future<void> discussion([String work = 'a']) async {
    await act('createDiscussion', {
      'id': 'talk',
      'title': '构思讨论',
      'chapterId': 'chapter-1',
    }, target: CommandTarget.work(work));
  }

  LibraryCommand send(String id, {String work = 'a', String body = '审稿建议'}) =>
      command(
        id,
        repository.workspace.revision,
        'sendDiscussionMessage',
        {'messageId': 'author-$id', 'body': body},
        target: CommandTarget.discussion(workId: work, discussionId: 'talk'),
      );
  Discussion talk([String work = 'a']) =>
      repository.workspace.work(work).discussions.single;
  DiscussionSource source() => DiscussionSource(
    workId: 'a',
    discussionId: 'talk',
    messageId: talk().messages.last.id,
  );
  Future<void> library() async {
    await act('createLibrary', {
      'id': 'k',
      'name': '资料库',
    }, target: CommandTarget.catalog());
  }

  Json document(
    DiscussionSource from, {
    String id = 'v1',
    String kind = 'reference',
  }) => KnowledgeVersion(
    id: id,
    title: '讨论成果',
    kind: kind,
    body: '作者选择的成果',
    associatedWorkId: 'a',
    provenance: SourceProvenance(
      writer: SourceWriter(kind: 'author', id: 'author'),
      sources: [from],
    ),
  ).toJson();
  Future<Json> adopt(
    DiscussionSource from, {
    String kind = 'reference',
    String? previous,
    String version = 'v1',
  }) => act('adoptDiscussionMessage', {
    'source': from.toJson(),
    'documentId': 'result',
    'expectedVersionId': previous,
    'version': document(from, id: version, kind: kind),
  }, target: CommandTarget.library('k', workId: 'a'));

  test('三轮持续讨论保留历史、固定来源和目标，不改变正文、设定、记忆或提案', () async {
    await discussion();
    await discussion('b');
    final before = repository.workspace.work('a');
    final b = repository.workspace.work('b').toJson();
    for (var i = 1; i <= 3; i++) {
      await service.execute(send('round-$i', body: '第 $i 轮'));
    }
    expect(talk().turns.map((t) => t.status), [
      'completed',
      'completed',
      'completed',
    ]);
    expect(talk().messages.length, 6);
    expect(
      model.contexts.map((c) => (c['discussionMessages'] as List).length),
      [1, 3, 5],
    );
    expect(
      model.contexts.every(
        (c) => c['workId'] == 'a' && c['chapterId'] == 'chapter-1',
      ),
      isTrue,
    );
    expect(
      repository.workspace.work('a').chapters.map((c) => c.toJson()),
      before.chapters.map((c) => c.toJson()),
    );
    expect(
      repository.workspace.work('a').memories.map((m) => m.toJson()),
      before.memories.map((m) => m.toJson()),
    );
    expect(repository.workspace.work('a').proposals, isEmpty);
    expect(repository.workspace.work('b').toJson(), b);
    expect(repository.workspace.libraries, isEmpty);
    service = LibraryService(repository);
    expect(
      (await service.snapshot())['workspace'],
      repository.workspace.toJson(),
    );
    expect(talk().messages.length, 6);
  });

  test('同请求合并和已完成复用，修改消息或目标冲突，不重复回复', () async {
    await discussion();
    await discussion('b');
    model.started = Completer();
    model.release = Completer();
    final original = send('same');
    final one = service.execute(original), two = service.execute(original);
    await model.started!.future;
    expect(talk().turns.single.status, 'pending');
    expect(talk().messages.length, 1);
    await expectLater(
      service.execute(
        command(
          'same',
          original.expectedRevision,
          'sendDiscussionMessage',
          original.payload,
          target: CommandTarget.discussion(workId: 'b', discussionId: 'talk'),
        ),
      ),
      throwsA(failure('request_conflict')),
    );
    model.release!.complete();
    await Future.wait([one, two]);
    final saved = repository.workspace.toJson();
    expect((await service.execute(original))['reused'], isTrue);
    expect(repository.workspace.toJson(), saved);
    expect(model.contexts.length, 1);
    expect(talk().messages.length, 2);
    await expectLater(
      service.execute(
        command(
          'same',
          original.expectedRevision,
          'sendDiscussionMessage',
          {'messageId': 'author-same', 'body': '不同内容'},
          target: original.target,
        ),
      ),
      throwsA(failure('request_conflict')),
    );
  });

  test('模型失败仅记录稳定错误码，原请求重试复用消息、上下文和来源', () async {
    await discussion();
    model.fail = true;
    final original = send('failed');
    await service.execute(original);
    expect(talk().turns.single.errorCode, 'model_failed');
    expect(talk().messages.length, 1);
    expect(repository.workspace.toJson().toString(), isNot(contains('供应商私有')));
    final captured = model.contexts.single;
    model.fail = false;
    await service.execute(original);
    expect(model.contexts.last, captured);
    expect(talk().turns.single.status, 'completed');
    expect(talk().messages.length, 2);
    model.output = ' ';
    await service.execute(send('invalid'));
    expect(talk().turns.last.errorCode, 'model_failed');
  });

  test('无模型保存失败轮次，已有成果可保存为参考、设定、计划且无需模型', () async {
    await discussion();
    await library();
    await service.execute(send('source'));
    final from = source();
    final before = repository.workspace.work('a');
    service = LibraryService(repository);
    for (final kind in ['reference', 'setting', 'plan']) {
      final original = command(
        'adopt-$kind',
        repository.workspace.revision,
        'adoptDiscussionMessage',
        {
          'source': from.toJson(),
          'documentId': kind,
          'expectedVersionId': null,
          'version': document(from, kind: kind),
        },
        target: CommandTarget.library('k', workId: 'a'),
      );
      await service.execute(original);
      final savedRevision = repository.workspace.revision;
      expect((await service.execute(original))['reused'], isTrue);
      expect(repository.workspace.revision, savedRevision);
    }
    expect(repository.workspace.library('k').documents.length, 3);
    expect(repository.workspace.work('a').knowledgeLinks, isEmpty);
    expect(
      repository.workspace.work('a').chapters.map((c) => c.toJson()),
      before.chapters.map((c) => c.toJson()),
    );
    expect(
      repository.workspace.work('a').memories.map((m) => m.toJson()),
      before.memories.map((m) => m.toJson()),
    );
    for (final doc in repository.workspace.library('k').documents) {
      expect(
        (doc.current.provenance.sources.single as DiscussionSource).toJson(),
        from.toJson(),
      );
    }
    await service.execute(send('unavailable'));
    expect(talk().turns.last.errorCode, 'model_unavailable');
    expect(talk().messages.last.role, 'author');
    expect(model.contexts.length, 1);
  });

  test('正文或采用版本变化后成果采用冲突，历史仍可看；资料更新需匹配 head', () async {
    await discussion();
    await library();
    await service.execute(send('source'));
    final from = source();
    await adopt(from);
    await expectLater(
      adopt(from, previous: 'old', version: 'v2'),
      throwsA(failure('version_conflict')),
    );
    expect(repository.workspace.library('k').documents.single.head, 'v1');
    await act('setKnowledgeLinks', {
      'links': [
        LibraryLink(libraryId: 'k', versions: {'result': 'v1'}).toJson(),
      ],
    });
    await expectLater(
      adopt(from, previous: 'v1', version: 'v2'),
      throwsA(failure('version_conflict')),
    );
    expect(talk().messages.length, 2);
    expect(
      repository.workspace.library('k').documents.single.versions.length,
      1,
    );
  });

  test('在途讨论允许切换目标视图；其他提交后仅原讨论记冲突，迟到回复不落入其他作品', () async {
    await discussion();
    await discussion('b');
    model.started = Completer();
    model.release = Completer();
    final original = send('late');
    final waiting = service.execute(original);
    await model.started!.future;
    await act('renameWork', {'title': 'B 新名'}, target: CommandTarget.work('b'));
    model.release!.complete();
    await waiting;
    expect(talk().turns.single.errorCode, 'version_conflict');
    expect(talk().messages.length, 1);
    expect(talk('b').messages, isEmpty);
    expect(repository.workspace.work('b').title, 'B 新名');
    model.started = null;
    model.release = null;
    await service.execute(
      original,
    ); // Unrelated rename does not invalidate the saved sources.
    expect(talk().turns.single.status, 'completed');
    expect(model.contexts.last, model.contexts.first);
  });

  test('来源正文变化后原请求重试不重新解释上下文，必须新一轮', () async {
    await discussion();
    model.fail = true;
    final original = send('stale');
    await service.execute(original);
    await act('saveChapter', {'chapterId': 'chapter-1', 'body': '作者新正文'});
    model.fail = false;
    await service.execute(original);
    expect(talk().turns.single.errorCode, 'version_conflict');
    expect(model.contexts.length, 1);
    await service.execute(send('fresh'));
    expect(talk().turns.last.status, 'completed');
    await expectLater(
      service.execute(original),
      throwsA(failure('discussion_unavailable')),
    );
    expect(talk().messages.length, 3);
  });

  test('讨论改稿由宿主拼接选段，拒绝不改正文，接受和恢复保持记忆与后续复查规则', () async {
    await discussion();
    await service.execute(send('edit'));
    final base = repository.workspace;
    final chapter = base.work('a').chapters.first;
    final from = source();
    WorkProposal proposed(String id) => discussionEditProposal(
      workspace: base,
      source: from,
      id: id,
      chapterId: chapter.id,
      start: 2,
      end: 5,
      replacement: '新的线索',
    );
    Future<void> save(WorkProposal proposal) async {
      await act('adoptDiscussionMessage', {
        'source': from.toJson(),
        'proposal': proposal.toJson(),
      });
    }

    await save(proposed('reject'));
    expect(repository.workspace.work('a').chapters.first.body, chapter.body);
    await act('rejectProposal', {'proposalId': 'reject'});
    expect(repository.workspace.work('a').chapters.first.body, chapter.body);
    final accept = proposed('accept');
    await save(accept);
    expect(
      accept.proposal.body,
      '${chapter.body.substring(0, 2)}新的线索${chapter.body.substring(5)}',
    );
    await act('acceptProposal', {'proposalId': 'accept'});
    expect(
      repository.workspace.work('a').chapters.first.body,
      accept.proposal.body,
    );
    expect(repository.workspace.workView('a').memoryFresh, isFalse);
    expect(repository.workspace.work('a').chapters.last.needsReview, isTrue);
    expect(
      repository.workspace.work('a').proposals.last.discussionSource!.toJson(),
      from.toJson(),
    );
    await act('restoreVersion', {
      'chapterId': chapter.id,
      'versionId': chapter.head,
    });
    expect(repository.workspace.workView('a').memoryFresh, isTrue);
    expect(repository.workspace.work('a').chapters.first.body, chapter.body);
  });

  test('伪造整章、错选段、旧来源或跨作品提案被拒绝，不授予讨论修改正文权限', () async {
    await discussion();
    await service.execute(send('source'));
    final from = source();
    final proposal = discussionEditProposal(
      workspace: repository.workspace,
      source: from,
      id: 'forged',
      chapterId: 'chapter-1',
      start: 0,
      end: 1,
      replacement: '替换',
    );
    final forged = proposal.toJson();
    forged['proposal'] = {...(forged['proposal'] as Json), 'body': '篡改选段外全文'};
    await expectLater(
      act('adoptDiscussionMessage', {
        'source': from.toJson(),
        'proposal': forged,
      }),
      throwsA(failure('invalid_selection')),
    );
    expect(repository.workspace.work('a').proposals, isEmpty);
    await act('saveChapter', {'chapterId': 'chapter-1', 'body': '新版本'});
    await expectLater(
      act('adoptDiscussionMessage', {
        'source': from.toJson(),
        'proposal': proposal.toJson(),
      }),
      throwsA(failure('version_conflict')),
    );
    expect(
      () => command(
        'cross',
        repository.workspace.revision,
        'adoptDiscussionMessage',
        {'source': from.toJson(), 'proposal': proposal.toJson()},
        target: CommandTarget.work('b'),
      ),
      throwsFormatException,
    );
  });

  test('仅重命名知识库后原请求重试上下文完全相同', () async {
    await discussion();
    await library();
    await service.execute(send('seed'));
    await adopt(source());
    await act('setKnowledgeLinks', {
      'links': [
        LibraryLink(libraryId: 'k', versions: {'result': 'v1'}).toJson(),
      ],
    });
    model.fail = true;
    final original = send('retry-name');
    await service.execute(original);
    final captured = model.contexts.last;
    await act('renameLibrary', {
      'name': '改名后的库',
    }, target: CommandTarget.library('k'));
    model.fail = false;
    await service.execute(original);
    expect(model.contexts.last, captured);
  });

  test('新建讨论的非法章节、重复编号和陈旧修订号不提交', () async {
    final original = repository.workspace.toJson();
    await expectLater(
      act('createDiscussion', {
        'id': 'talk',
        'title': '非法关联',
        'chapterId': 'missing',
      }),
      throwsA(failure('target_missing')),
    );
    expect(repository.workspace.toJson(), original);
    await discussion();
    await expectLater(discussion(), throwsA(failure('target_exists')));
    await expectLater(
      service.execute(
        command('old', 0, 'createDiscussion', {
          'id': 'other',
          'title': '旧请求',
          'chapterId': null,
        }, target: CommandTarget.work('a')),
      ),
      throwsA(failure('version_conflict')),
    );
  });
}
