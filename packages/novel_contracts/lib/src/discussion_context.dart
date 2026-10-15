import 'dart:convert';

import 'library.dart';
import 'knowledge_context.dart';
import 'workspace.dart';

/// Reconstruct immutable sources for a saved turn, including an exact retry.
Json discussionContext(
  LibraryWorkspace workspace,
  String discussionId,
  DiscussionTurn turn,
) {
  final basis = turn.basis;
  final work = workspace.work(basis.workId);
  final discussion = work.discussions.firstWhere((d) => d.id == discussionId);
  final refs = [...(turn.readDocuments ?? basis.documents)]
    ..sort((a, b) {
      final library = a.libraryId.compareTo(b.libraryId);
      return library != 0 ? library : a.documentId.compareTo(b.documentId);
    });
  final authorIndex = discussion.messages.indexWhere(
    (m) => m.id == turn.authorMessageId,
  );
  return {
    'workId': work.id,
    'basis': basis.toJson(),
    'discussionId': discussionId,
    'chapterId': discussion.chapterId,
    if (turn.readDocuments != null) ...{
      'knowledgeCatalog': knowledgeCatalog(workspace, basis),
      'readDocuments': refs.map((ref) => ref.toJson()).toList(),
    },
    'documents': [
      for (final ref in refs)
        SourceDocument(
          id: jsonEncode([ref.libraryId, ref.documentId]),
          title: workspace.documentVersion(ref).title,
          kind: workspace.documentVersion(ref).kind,
          body: workspace.documentVersion(ref).body,
        ).toJson(),
    ],
    'knowledgeDocuments': [
      for (final ref in refs)
        {...ref.toJson(), 'version': workspace.documentVersion(ref).toJson()},
    ],
    'acceptedChapters': [
      for (final chapter in work.chapters)
        if (basis.chapterHeads.containsKey(chapter.id))
          {
            'chapterId': chapter.id,
            'versionId': basis.chapterHeads[chapter.id],
            'number': chapter.number,
            'title': chapter.title,
            'body': chapter.versions
                .firstWhere((v) => v.id == basis.chapterHeads[chapter.id])
                .body,
          },
    ],
    'discussionMessages': discussion.messages
        .take(authorIndex + 1)
        .map((m) => m.toJson())
        .toList(),
  };
}

/// Both clients and the host assemble an edit from a validated nonempty range.
/// The host calls this again; a caller-supplied full chapter grants no authority.
WorkProposal discussionEditProposal({
  required LibraryWorkspace workspace,
  required DiscussionSource source,
  required String id,
  required String chapterId,
  required int start,
  required int end,
  required String replacement,
}) {
  final message = workspace.discussionMessage(source);
  final turn = workspace.discussionTurn(source);
  if (!workspace.isBasisCurrent(turn.basis)) {
    throw const FormatException('讨论所依据的正文或采用资料版本已改变');
  }
  final chapter = workspace
      .work(source.workId)
      .chapters
      .firstWhere(
        (c) => c.id == chapterId,
        orElse: () => throw const FormatException('目标章节不存在'),
      );
  bool boundary(int at) =>
      at == 0 ||
      at == chapter.body.length ||
      !(chapter.body.codeUnitAt(at) >= 0xdc00 &&
          chapter.body.codeUnitAt(at) <= 0xdfff &&
          chapter.body.codeUnitAt(at - 1) >= 0xd800 &&
          chapter.body.codeUnitAt(at - 1) <= 0xdbff);
  if (start < 0 ||
      end <= start ||
      end > chapter.body.length ||
      !boundary(start) ||
      !boundary(end) ||
      replacement.trim().isEmpty ||
      replacement.length > 100000) {
    throw const FormatException('选段或替换文本无效');
  }
  final candidate = chapter.body.replaceRange(start, end, replacement);
  if (candidate.length > 100000) {
    throw const FormatException('改写后的整章超过限制');
  }
  return WorkProposal(
    workId: source.workId,
    documents: turn.basis.documents,
    discussionSource: source,
    proposal: Proposal(
      id: id,
      chapterId: chapterId,
      title: chapter.title,
      body: candidate,
      baseHeads: turn.basis.chapterHeads,
      baseRevision: turn.basis.revision,
      status: 'pending',
      provider: message.provider ?? 'author/discussion',
      context: {
        ...discussionContext(workspace, source.discussionId, turn),
        'discussionSource': source.toJson(),
        'selection': {
          'chapterId': chapterId,
          'versionId': chapter.head,
          'start': start,
          'end': end,
          'text': chapter.body.substring(start, end),
        },
        'replacement': replacement,
      },
      usage: {},
    ),
  );
}
