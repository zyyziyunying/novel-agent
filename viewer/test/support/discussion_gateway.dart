import 'dart:async';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_gateway.dart';

import 'library_gateway.dart';

/// UI fixture only; domain, HTTP and persistence acceptance use the real service.
class DiscussionGateway extends FakeLibraryGateway {
  Completer<void>? replyRelease;
  bool failReply = false;
  bool loseFinishedResponse = false;
  bool losePendingResponse = false;
  @override
  Future<LibraryResult> execute(LibraryCommand command) async {
    if (!{
      'createDiscussion',
      'sendDiscussionMessage',
      'adoptDiscussionMessage',
    }.contains(command.operation)) {
      return super.execute(command);
    }
    commands.add(command);
    final receipt = workspace.receipts[command.requestId];
    if (receipt != null && command.operation != 'sendDiscussionMessage') {
      return result();
    }
    if (receipt == null && command.expectedRevision != workspace.revision) {
      throw const GatewayFailure('版本冲突');
    }
    if (command.operation == 'createDiscussion') {
      final work = workspace.work(command.target.workId!);
      _commit(
        work: _work(
          work,
          discussions: [
            ...work.discussions,
            Discussion(
              id: command.payload['id'],
              title: command.payload['title'],
              chapterId: command.payload['chapterId'],
              messages: [],
              turns: [],
            ),
          ],
        ),
        command: command,
      );
    } else if (command.operation == 'sendDiscussionMessage') {
      var work = workspace.work(command.target.workId!);
      var d = work.discussions.firstWhere(
        (d) => d.id == command.target.discussionId,
      );
      var turn = d.turns
          .where((t) => t.requestId == command.requestId)
          .firstOrNull;
      if (turn?.status == 'completed') return result();
      if (turn == null) {
        turn = DiscussionTurn(
          requestId: command.requestId,
          authorMessageId: command.payload['messageId'],
          status: 'pending',
          assistantMessageId: null,
          errorCode: null,
          basis: workspace.captureBasis(work.id),
        );
        d = Discussion(
          id: d.id,
          title: d.title,
          chapterId: d.chapterId,
          messages: [
            ...d.messages,
            DiscussionMessage(
              id: turn.authorMessageId,
              role: 'author',
              body: command.payload['body'],
              provider: null,
            ),
          ],
          turns: [...d.turns, turn],
        );
        _commit(
          work: _work(
            work,
            discussions: [
              for (final old in work.discussions) old.id == d.id ? d : old,
            ],
          ),
          command: command,
        );
      }
      if (losePendingResponse) {
        throw const GatewayFailure('连接中断', uncertain: true);
      }
      if (replyRelease != null) await replyRelease!.future;
      work = workspace.work(work.id);
      d = work.discussions.firstWhere(
        (d) => d.id == command.target.discussionId,
      );
      final reply = DiscussionMessage(
        id: 'reply-${command.requestId}',
        role: 'assistant',
        body: '讨论建议：${command.payload['body']}',
        provider: 'fixture/local',
      );
      final finished = DiscussionTurn(
        requestId: turn.requestId,
        authorMessageId: turn.authorMessageId,
        status: failReply ? 'failed' : 'completed',
        assistantMessageId: failReply ? null : reply.id,
        errorCode: failReply ? 'model_failed' : null,
        basis: turn.basis,
      );
      d = Discussion(
        id: d.id,
        title: d.title,
        chapterId: d.chapterId,
        messages: [...d.messages, if (!failReply) reply],
        turns: [
          for (final t in d.turns) t.requestId == turn.requestId ? finished : t,
        ],
      );
      _commit(
        work: _work(
          work,
          discussions: [
            for (final old in work.discussions) old.id == d.id ? d : old,
          ],
        ),
      );
      if (loseFinishedResponse) {
        throw const GatewayFailure('迟到网络失败', uncertain: true);
      }
    } else {
      final source = DiscussionSource.fromJson(command.payload['source']);
      if (!workspace.isBasisCurrent(workspace.discussionTurn(source).basis)) {
        throw const GatewayFailure('讨论来源版本冲突');
      }
      if (command.target.kind == 'library') {
        final version = KnowledgeVersion.fromJson(command.payload['version']);
        final library = workspace.library(command.target.libraryId!);
        _commit(
          libraries: [
            for (final l in workspace.libraries)
              l.id == library.id
                  ? KnowledgeLibrary(
                      id: l.id,
                      name: l.name,
                      documents: [
                        ...l.documents,
                        KnowledgeDocument(
                          id: command.payload['documentId'],
                          head: version.id,
                          versions: [version],
                        ),
                      ],
                    )
                  : l,
          ],
          command: command,
        );
      } else {
        final work = workspace.work(source.workId);
        _commit(
          work: _work(
            work,
            proposals: [
              ...work.proposals,
              WorkProposal.fromJson(command.payload['proposal']),
            ],
          ),
          command: command,
        );
      }
    }
    return response == null ? result() : response!.future;
  }

  NovelWork _work(
    NovelWork work, {
    List<Discussion>? discussions,
    List<WorkProposal>? proposals,
  }) => NovelWork(
    id: work.id,
    title: work.title,
    knowledgeLinks: work.knowledgeLinks,
    chapters: work.chapters,
    proposals: proposals ?? work.proposals,
    memories: work.memories,
    discussions: discussions ?? work.discussions,
  );
  void _commit({
    NovelWork? work,
    List<KnowledgeLibrary>? libraries,
    LibraryCommand? command,
  }) {
    workspace = LibraryWorkspace(
      revision: workspace.revision + 1,
      works: [for (final w in workspace.works) w.id == work?.id ? work! : w],
      libraries: libraries ?? workspace.libraries,
      receipts: {
        ...workspace.receipts,
        if (command != null)
          command.requestId: BoundReceipt(
            fingerprint: 'ui-fixture',
            revision: workspace.revision + 1,
            target: command.target,
          ),
      },
    );
  }
}
