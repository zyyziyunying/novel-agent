part of 'library_controller.dart';

class DiscussionRequestState {
  bool busy = false;
  String? error;
  LibraryCommand? pending;
}

String discussionFailure(String? code) => switch (code) {
  'model_unavailable' => '未配置模型，记录可查看，成果仍可保存到知识库。',
  'model_failed' => '模型调用失败或回复无效，请重试本轮。',
  'interrupted' => '本轮已中断，请重试本轮以继续原请求。',
  'version_conflict' => '正文或资料来源已变化，回复未采用。请发起新一轮讨论。',
  _ => '结果尚未确认，请刷新或用原请求重试。',
};

extension DiscussionActions on LibraryController {
  DiscussionRequestState discussionState(String workId, String discussionId) =>
      discussionRequests.putIfAbsent((
        workId,
        discussionId,
      ), DiscussionRequestState.new);

  Discussion? selectedDiscussion(String workId) {
    final discussions = workspace!.work(workId).discussions;
    return discussions
            .where((d) => d.id == selectedDiscussions[workId])
            .firstOrNull ??
        discussions.firstOrNull;
  }

  void selectDiscussion(String workId, String id) {
    selectedDiscussions[workId] = id;
    _changed();
  }

  Future<bool> createDiscussion(
    String workId,
    String id,
    String title,
    String? chapterId,
  ) => _catalog('createDiscussion', CommandTarget.work(workId), {
    'id': id,
    'title': title,
    'chapterId': chapterId,
  });

  Future<bool> adoptDiscussionKnowledge({
    required DiscussionSource source,
    required String libraryId,
    required String documentId,
    required KnowledgeVersion version,
  }) => _catalog(
    'adoptDiscussionMessage',
    CommandTarget.library(libraryId, workId: version.associatedWorkId),
    {
      'source': source.toJson(),
      'documentId': documentId,
      'expectedVersionId': null,
      'version': version.toJson(),
    },
  );

  Future<bool> adoptDiscussionEdit(
    DiscussionSource source,
    WorkProposal proposal,
  ) => _catalog('adoptDiscussionMessage', CommandTarget.work(source.workId), {
    'source': source.toJson(),
    'proposal': proposal.toJson(),
  });

  Future<bool> sendDiscussion(String workId, String discussionId, String body) {
    final command = LibraryCommand(
      requestId: '$_session-${++_sequence}',
      expectedRevision: workspace!.revision,
      target: CommandTarget.discussion(
        workId: workId,
        discussionId: discussionId,
      ),
      operation: 'sendDiscussionMessage',
      payload: {'messageId': newKnowledgeId('message'), 'body': body},
    );
    return _runDiscussion(command);
  }

  Future<bool> retryDiscussion(
    String workId,
    String discussionId,
    String requestId,
  ) {
    final state = discussionState(workId, discussionId);
    if (state.pending != null) return _runDiscussion(state.pending!);
    final discussion = workspace!
        .work(workId)
        .discussions
        .firstWhere((d) => d.id == discussionId);
    final turn = discussion.turns.firstWhere((t) => t.requestId == requestId);
    final author = discussion.messages.firstWhere(
      (m) => m.id == turn.authorMessageId,
    );
    return _runDiscussion(
      LibraryCommand(
        requestId: turn.requestId,
        expectedRevision: turn.basis.revision,
        target: CommandTarget.discussion(
          workId: workId,
          discussionId: discussionId,
        ),
        operation: 'sendDiscussionMessage',
        payload: {'messageId': author.id, 'body': author.body},
      ),
    );
  }

  DiscussionTurn? _discussionTurn(LibraryCommand command) => workspace?.works
      .where((w) => w.id == command.target.workId)
      .firstOrNull
      ?.discussions
      .where((d) => d.id == command.target.discussionId)
      .firstOrNull
      ?.turns
      .where((t) => t.requestId == command.requestId)
      .firstOrNull;

  Future<bool> _runDiscussion(LibraryCommand command) async {
    final state = discussionState(
      command.target.workId!,
      command.target.discussionId!,
    );
    if (_disposed ||
        state.busy ||
        busy ||
        (hasPending && state.pending?.requestId != command.requestId)) {
      return false;
    }
    state.busy = true;
    state.error = null;
    _changed();
    try {
      _apply(await gateway.execute(command));
      final turn = _discussionTurn(command);
      state.pending = turn?.status == 'pending' ? command : null;
      if (turn?.status == 'completed') return true;
      state.error = discussionFailure(turn?.errorCode);
    } on GatewayFailure catch (failure) {
      final turn = _discussionTurn(command);
      if (turn?.status == 'completed') {
        state.pending = null;
        return true;
      }
      state.pending =
          failure.uncertain && (turn == null || turn.status == 'pending')
          ? command
          : null;
      state.error = turn?.status == 'failed'
          ? discussionFailure(turn!.errorCode)
          : failure.message;
    } on Object {
      state.pending = command;
      state.error = '结果尚未确认，请刷新或重试本轮。';
    } finally {
      state.busy = false;
      _changed();
    }
    return false;
  }
}
