part of 'library_service.dart';

extension _DiscussionService on LibraryService {
  NovelWork _withDiscussions(
    NovelWork work,
    List<Discussion> discussions, {
    List<WorkProposal>? proposals,
  }) => NovelWork(
    id: work.id,
    title: work.title,
    knowledgeLinks: work.knowledgeLinks,
    chapters: work.chapters,
    proposals: proposals ?? work.proposals,
    memories: work.memories,
    discussions: discussions,
  );

  Discussion _discussion(LibraryWorkspace workspace, CommandTarget target) =>
      workspace
          .work(target.workId!)
          .discussions
          .firstWhere((d) => d.id == target.discussionId);

  Future<void> _recoverDiscussions() async {
    final base = await repository.load();
    var changed = false;
    final works = [
      for (final work in base.works)
        _withDiscussions(work, [
          for (final discussion in work.discussions)
            Discussion(
              id: discussion.id,
              title: discussion.title,
              chapterId: discussion.chapterId,
              messages: discussion.messages,
              turns: [
                for (final turn in discussion.turns)
                  if (turn.status == 'pending')
                    (() {
                      changed = true;
                      return _turnState(turn, 'failed', error: 'interrupted');
                    })()
                  else
                    turn,
              ],
            ),
        ]),
    ];
    if (changed) {
      await repository.save(
        LibraryWorkspace(
          revision: base.revision + 1,
          works: works,
          libraries: base.libraries,
          receipts: base.receipts,
        ),
        base.revision,
      );
    }
  }

  DiscussionTurn _turnState(
    DiscussionTurn turn,
    String status, {
    String? reply,
    String? error,
  }) => DiscussionTurn(
    requestId: turn.requestId,
    authorMessageId: turn.authorMessageId,
    status: status,
    assistantMessageId: reply,
    errorCode: error,
    basis: turn.basis,
  );

  Future<LibraryWorkspace> _saveDiscussion(
    LibraryWorkspace base,
    String workId,
    Discussion discussion,
  ) async {
    final owner = base.work(workId);
    final replacement = _withDiscussions(owner, [
      for (final d in owner.discussions) d.id == discussion.id ? discussion : d,
    ]);
    final next = LibraryWorkspace(
      revision: base.revision + 1,
      works: [for (final w in base.works) w.id == workId ? replacement : w],
      libraries: base.libraries,
      receipts: base.receipts,
    );
    await repository.save(next, base.revision);
    return next;
  }

  Discussion _replaceTurn(
    Discussion discussion,
    DiscussionTurn turn, {
    DiscussionMessage? reply,
  }) => Discussion(
    id: discussion.id,
    title: discussion.title,
    chapterId: discussion.chapterId,
    messages: [...discussion.messages, ?reply],
    turns: [
      for (final t in discussion.turns)
        t.requestId == turn.requestId ? turn : t,
    ],
  );

  Future<Json> _sendDiscussion(
    LibraryCommand command,
    String fingerprint,
  ) async {
    final start = await _locked(() async {
      var base = await repository.load();
      final reused = _check(base, command, fingerprint);
      var discussion = _discussion(base, command.target);
      if (reused) {
        final turn = discussion.turns.firstWhere(
          (t) => t.requestId == command.requestId,
        );
        if (turn.status == 'completed') return (base, false);
        if (discussion.turns.last.requestId != turn.requestId) {
          throw const LibraryFailure(
            'discussion_unavailable',
            '该轮之后已有新讨论，请查看原记录并发起新一轮。',
          );
        }
        if (!base.isBasisCurrent(turn.basis)) {
          if (turn.errorCode != 'version_conflict') {
            base = await _saveDiscussion(
              base,
              command.target.workId!,
              _replaceTurn(
                discussion,
                _turnState(turn, 'failed', error: 'version_conflict'),
              ),
            );
          }
          return (base, false);
        }
        if (turn.status != 'pending') {
          base = await _saveDiscussion(
            base,
            command.target.workId!,
            _replaceTurn(discussion, _turnState(turn, 'pending')),
          );
        }
      } else {
        if (discussion.turns.any((t) => t.status == 'pending')) {
          throw const LibraryFailure('discussion_busy', '当前讨论正在回复，请稍后或用原请求重试。');
        }
        final messageId = command.payload['messageId'] as String;
        if (discussion.messages.any((m) => m.id == messageId)) {
          throw const LibraryFailure('target_exists', '讨论消息编号已存在。');
        }
        final turn = DiscussionTurn(
          requestId: command.requestId,
          authorMessageId: messageId,
          status: 'pending',
          assistantMessageId: null,
          errorCode: null,
          basis: base.captureBasis(command.target.workId!),
        );
        discussion = Discussion(
          id: discussion.id,
          title: discussion.title,
          chapterId: discussion.chapterId,
          messages: [
            ...discussion.messages,
            DiscussionMessage(
              id: messageId,
              role: 'author',
              body: command.payload['body'],
              provider: null,
            ),
          ],
          turns: [...discussion.turns, turn],
        );
        final work = base.work(command.target.workId!);
        final replacement = _withDiscussions(work, [
          for (final d in work.discussions)
            d.id == discussion.id ? discussion : d,
        ]);
        final result = await _commit(base, command, fingerprint, [
          for (final w in base.works) w.id == work.id ? replacement : w,
        ], base.libraries);
        base = LibraryWorkspace.fromJson(result['workspace']);
      }
      return (base, true);
    });
    if (!start.$2) return _result(start.$1, reused: true);
    final running = start.$1;
    final discussion = _discussion(running, command.target);
    final turn = discussion.turns.firstWhere(
      (t) => t.requestId == command.requestId,
    );
    String? body;
    String? error;
    final discussionModel = model;
    if (discussionModel is! DiscussionModel) {
      error = 'model_unavailable';
    } else {
      try {
        body = await (discussionModel as DiscussionModel).discuss(
          discussionContext(running, discussion.id, turn),
          discussion.messages
              .firstWhere((m) => m.id == turn.authorMessageId)
              .body,
        );
        if (body.trim().isEmpty || body.length > 100000) {
          throw const FormatException('讨论回复无效');
        }
      } on Object {
        error = 'model_failed';
      }
    }
    return _locked(() async {
      final current = await repository.load();
      final latest = _discussion(current, command.target);
      final saved = latest.turns.firstWhere(
        (t) => t.requestId == turn.requestId,
      );
      if (saved.status == 'completed') return _result(current, reused: true);
      if (current.revision != running.revision ||
          !current.isBasisCurrent(turn.basis)) {
        error = 'version_conflict';
      }
      DiscussionMessage? reply;
      if (error == null) {
        var id = 'reply-${sha256.convert(utf8.encode(command.requestId))}';
        while (latest.messages.any((m) => m.id == id)) {
          id = '$id-r';
        }
        reply = DiscussionMessage(
          id: id,
          role: 'assistant',
          body: body!,
          provider: model!.name,
        );
      }
      final next = await _saveDiscussion(
        current,
        command.target.workId!,
        _replaceTurn(
          latest,
          _turnState(
            saved,
            error == null ? 'completed' : 'failed',
            reply: reply?.id,
            error: error,
          ),
          reply: reply,
        ),
      );
      return _result(next);
    });
  }

  (List<NovelWork>, List<KnowledgeLibrary>) _applyDiscussion(
    LibraryWorkspace base,
    LibraryCommand command,
  ) {
    if (command.operation == 'createDiscussion') {
      final work = base.work(command.target.workId!);
      if (work.discussions.any((d) => d.id == command.payload['id'])) {
        throw const LibraryFailure('target_exists', '讨论编号已存在。');
      }
      final chapterId = command.payload['chapterId'];
      if (chapterId != null && !work.chapters.any((c) => c.id == chapterId)) {
        throw const LibraryFailure('target_missing', '讨论关联的章节不存在。');
      }
      final replacement = _withDiscussions(work, [
        ...work.discussions,
        Discussion(
          id: command.payload['id'],
          title: command.payload['title'],
          chapterId: chapterId,
          messages: [],
          turns: [],
        ),
      ]);
      return (
        [for (final w in base.works) w.id == work.id ? replacement : w],
        base.libraries,
      );
    }
    final source = DiscussionSource.fromJson(command.payload['source']);
    DiscussionTurn turn;
    try {
      turn = base.discussionTurn(source);
    } on FormatException {
      throw const LibraryFailure('target_missing', '所选讨论消息不存在。');
    }
    if (!base.isBasisCurrent(turn.basis)) {
      throw const LibraryFailure(
        'version_conflict',
        '讨论所依据的正文或采用资料版本已改变，请重新讨论。',
      );
    }
    if (command.target.kind == 'library') {
      final library = base.library(command.target.libraryId!);
      final changed = KnowledgeLibrary(
        id: library.id,
        name: library.name,
        documents: _saveDocument(library, command.payload),
      );
      return (
        base.works,
        [for (final l in base.libraries) l.id == library.id ? changed : l],
      );
    }
    final supplied = WorkProposal.fromJson(command.payload['proposal']);
    final work = base.work(source.workId);
    if (work.proposals.any((p) => p.proposal.id == supplied.proposal.id)) {
      throw const LibraryFailure('target_exists', '提案编号已存在。');
    }
    WorkProposal proposed;
    try {
      final selection = object(supplied.proposal.context['selection'], {
        'chapterId',
        'versionId',
        'start',
        'end',
        'text',
      });
      proposed = discussionEditProposal(
        workspace: base,
        source: source,
        id: supplied.proposal.id,
        chapterId: supplied.proposal.chapterId,
        start: integer(selection['start']),
        end: integer(selection['end']),
        replacement: readText(supplied.proposal.context['replacement']),
      );
      if (!(proposed.proposal.context['selection'] as Json).entries.every(
            (entry) => selection[entry.key] == entry.value,
          ) ||
          supplied.proposal.body != proposed.proposal.body ||
          supplied.proposal.baseRevision != turn.basis.revision ||
          !sameHeads(supplied.proposal.baseHeads, turn.basis.chapterHeads) ||
          supplied.documents.toSet().length != turn.basis.documents.length ||
          !turn.basis.documents.every(supplied.documents.contains)) {
        throw const FormatException('提案不符合讨论来源和选段边界');
      }
    } on FormatException {
      throw const LibraryFailure('invalid_selection', '提案来源、选段或替换文本无效；正文未改变。');
    }
    final replacement = _withDiscussions(
      work,
      work.discussions,
      proposals: [...work.proposals, proposed],
    );
    return (
      [for (final w in base.works) w.id == work.id ? replacement : w],
      base.libraries,
    );
  }
}
