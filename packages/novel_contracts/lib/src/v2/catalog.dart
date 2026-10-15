import '../workspace.dart';
import 'discussion.dart';
import 'knowledge.dart';
import 'targets.dart';
import 'validation.dart';

class WorkProposal {
  WorkProposal({
    required this.workId,
    required Proposal proposal,
    required List<DocumentReference> documents,
    required this.discussionSource,
  }) : proposal = Proposal.fromJson(immutableJson(proposal.toJson())),
       documents = List.unmodifiable(documents) {
    identifier(workId);
    identifier(proposal.id);
    identifier(proposal.chapterId);
    if (discussionSource != null && discussionSource!.workId != workId) {
      throw const FormatException('讨论提案来源不属于目标作品');
    }
    basis; // Validate the typed source manifest too.
  }
  final String workId;
  final Proposal proposal;
  final List<DocumentReference> documents;
  final DiscussionSource? discussionSource;
  GenerationBasis get basis => GenerationBasis(
    workId: workId,
    revision: proposal.baseRevision,
    chapterHeads: proposal.baseHeads,
    documents: documents,
  );
  Json toJson() => {
    'workId': workId,
    'proposal': proposal.toJson(),
    'documents': documents.map((d) => d.toJson()).toList(),
    'discussionSource': discussionSource?.toJson(),
  };
  factory WorkProposal.fromJson(Object? value) {
    final j = object(value, {
      'workId',
      'proposal',
      'documents',
      'discussionSource',
    });
    return WorkProposal(
      workId: identifier(j['workId']),
      proposal: Proposal.fromJson(j['proposal']),
      documents: items(j['documents'], DocumentReference.fromJson),
      discussionSource: j['discussionSource'] == null
          ? null
          : DiscussionSource.fromJson(j['discussionSource']),
    );
  }
}

class NovelWork {
  NovelWork({
    required this.id,
    required this.title,
    required List<LibraryLink> knowledgeLinks,
    required List<Chapter> chapters,
    required List<WorkProposal> proposals,
    required List<MemorySnapshot> memories,
    required List<Discussion> discussions,
  }) : knowledgeLinks = List.unmodifiable(knowledgeLinks),
       chapters = List.unmodifiable(
         chapters.map((c) => Chapter.fromJson(c.toJson())),
       ),
       proposals = List.unmodifiable(proposals),
       memories = List.unmodifiable(
         memories.map((m) => MemorySnapshot.fromJson(m.toJson())),
       ),
       discussions = List.unmodifiable(discussions) {
    identifier(id);
    readText(title);
    uniqueIds(knowledgeLinks.map((l) => l.libraryId));
    uniqueIds(this.chapters.map((c) => c.id));
    uniqueIds(proposals.map((p) => p.proposal.id));
    uniqueIds(this.memories.map((m) => m.id));
    uniqueIds(discussions.map((d) => d.id));
    for (final chapter in this.chapters) {
      uniqueIds(chapter.versions.map((v) => v.id));
      identifier(chapter.head);
    }
    if (proposals.any((p) => p.workId != id) ||
        discussions.any(
          (d) =>
              d.chapterId != null &&
              !this.chapters.any((c) => c.id == d.chapterId),
        )) {
      throw const FormatException('提案或讨论不属于目标作品');
    }
    // Reuse the existing chapter/order/evidence invariants, not its v1 storage.
    Workspace(
      revision: 0,
      title: title,
      documents: [],
      chapters: this.chapters,
      proposals: proposals.map((p) => p.proposal).toList(),
      memories: this.memories,
      receipts: {},
    );
  }
  final String id;
  final String title;
  final List<LibraryLink> knowledgeLinks;
  final List<Chapter> chapters;
  final List<WorkProposal> proposals;
  final List<MemorySnapshot> memories;
  final List<Discussion> discussions;
  Map<String, String> get currentHeads => {
    for (final c in chapters) c.id: c.head,
  };
  List<DocumentReference> get adoptedDocuments => [
    for (final link in knowledgeLinks) ...link.references,
  ];
  Json toJson() => {
    'id': id,
    'title': title,
    'knowledgeLinks': knowledgeLinks.map((l) => l.toJson()).toList(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
    'memories': memories.map((m) => m.toJson()).toList(),
    'discussions': discussions.map((d) => d.toJson()).toList(),
  };
  factory NovelWork.fromJson(Object? value) {
    final j = object(value, {
      'id',
      'title',
      'knowledgeLinks',
      'chapters',
      'proposals',
      'memories',
      'discussions',
    });
    return NovelWork(
      id: identifier(j['id']),
      title: readText(j['title']),
      knowledgeLinks: items(j['knowledgeLinks'], LibraryLink.fromJson),
      chapters: items(j['chapters'], Chapter.fromJson),
      proposals: items(j['proposals'], WorkProposal.fromJson),
      memories: items(j['memories'], MemorySnapshot.fromJson),
      discussions: items(j['discussions'], Discussion.fromJson),
    );
  }
}

class BoundReceipt {
  BoundReceipt({
    required this.fingerprint,
    required this.revision,
    required this.target,
  }) {
    readText(fingerprint);
    integer(revision);
  }
  final String fingerprint;
  final int revision;
  final CommandTarget target;
  Json toJson() => {
    'fingerprint': fingerprint,
    'revision': revision,
    'target': target.toJson(),
  };
  factory BoundReceipt.fromJson(Object? value) {
    final j = object(value, {'fingerprint', 'revision', 'target'});
    return BoundReceipt(
      fingerprint: readText(j['fingerprint']),
      revision: integer(j['revision']),
      target: CommandTarget.fromJson(j['target']),
    );
  }
}

class LibraryWorkspace {
  LibraryWorkspace({
    required this.revision,
    required List<NovelWork> works,
    required List<KnowledgeLibrary> libraries,
    required Map<String, BoundReceipt> receipts,
  }) : works = List.unmodifiable(works),
       libraries = List.unmodifiable(libraries),
       receipts = Map.unmodifiable(receipts) {
    integer(revision);
    uniqueIds(works.map((w) => w.id));
    uniqueIds(libraries.map((l) => l.id));
    uniqueIds(receipts.keys);
    uniqueIds(
      works.expand(
        (w) => w.discussions.expand((d) => d.turns.map((t) => t.requestId)),
      ),
    );
    for (final work in works) {
      for (final link in work.knowledgeLinks) {
        library(link.libraryId);
        for (final ref in link.references) {
          documentVersion(ref);
        }
      }
      for (final proposal in work.proposals) {
        validateBasis(proposal.basis);
        if (proposal.discussionSource != null) {
          final original = discussionTurn(proposal.discussionSource!).basis;
          final proposed = proposal.basis;
          final documents = original.documents.toSet();
          if (!sameHeads(original.chapterHeads, proposed.chapterHeads) ||
              documents.length != proposed.documents.length ||
              !proposed.documents.every(documents.contains)) {
            throw const FormatException('提案与讨论的来源版本不一致');
          }
        }
      }
      for (final discussion in work.discussions) {
        for (final turn in discussion.turns) {
          final receipt = receipts[turn.requestId];
          if (receipt == null ||
              receipt.target.kind != 'discussion' ||
              receipt.target.workId != work.id ||
              receipt.target.discussionId != discussion.id) {
            throw const FormatException('讨论轮次必须有同目标的请求回执');
          }
          if (turn.basis.workId != work.id) {
            throw const FormatException('讨论上下文不属于目标作品');
          }
          validateBasis(turn.basis);
          if (turn.readDocuments != null &&
              turn.basis.documents.any(
                (ref) =>
                    documentVersion(ref).requiresFullText &&
                    !turn.readDocuments!.contains(ref),
              )) {
            throw const FormatException('讨论读取清单不能遗漏必读资料');
          }
        }
      }
    }
    for (final lib in libraries) {
      for (final doc in lib.documents) {
        for (final version in doc.versions) {
          if (version.associatedWorkId != null) work(version.associatedWorkId!);
          for (final source
              in version.provenance.sources.whereType<DiscussionSource>()) {
            discussionMessage(source);
          }
        }
      }
    }
    for (final receipt in receipts.values) {
      if (receipt.revision > revision) throw const FormatException('回执修订号超前');
      validateTarget(receipt.target);
    }
  }
  final int revision;
  final List<NovelWork> works;
  final List<KnowledgeLibrary> libraries;
  final Map<String, BoundReceipt> receipts;
  NovelWork work(String id) =>
      works.where((w) => w.id == id).firstOrNull ??
      (throw const FormatException('目标作品不存在'));
  KnowledgeLibrary library(String id) =>
      libraries.where((l) => l.id == id).firstOrNull ??
      (throw const FormatException('目标知识库不存在'));
  KnowledgeVersion documentVersion(DocumentReference ref) {
    final doc = library(
      ref.libraryId,
    ).documents.where((d) => d.id == ref.documentId).firstOrNull;
    final version = doc?.versions
        .where((v) => v.id == ref.versionId)
        .firstOrNull;
    return version ?? (throw const FormatException('资料来源版本不存在'));
  }

  DiscussionMessage discussionMessage(DiscussionSource ref) {
    final discussion = work(
      ref.workId,
    ).discussions.where((d) => d.id == ref.discussionId).firstOrNull;
    return discussion?.messages
            .where((m) => m.id == ref.messageId)
            .firstOrNull ??
        (throw const FormatException('讨论来源消息不存在'));
  }

  DiscussionTurn discussionTurn(DiscussionSource ref) {
    discussionMessage(ref);
    return work(ref.workId).discussions
        .firstWhere((d) => d.id == ref.discussionId)
        .turns
        .firstWhere(
          (t) =>
              t.authorMessageId == ref.messageId ||
              t.assistantMessageId == ref.messageId,
        );
  }

  void validateTarget(CommandTarget target) {
    if (target.workId != null) work(target.workId!);
    if (target.libraryId != null) library(target.libraryId!);
    if (target.kind == 'discussion' &&
        !work(
          target.workId!,
        ).discussions.any((d) => d.id == target.discussionId)) {
      throw const FormatException('目标讨论不存在');
    }
  }

  void validateBasis(GenerationBasis basis) {
    final owner = work(basis.workId);
    if (basis.revision > revision) throw const FormatException('上下文修订号超前');
    for (final entry in basis.chapterHeads.entries) {
      final chapter = owner.chapters
          .where((c) => c.id == entry.key)
          .firstOrNull;
      if (chapter == null ||
          !chapter.versions.any((v) => v.id == entry.value)) {
        throw const FormatException('正文来源版本不存在');
      }
    }
    for (final ref in basis.documents) {
      documentVersion(ref);
    }
  }

  GenerationBasis captureBasis(String workId) {
    final owner = work(workId);
    return GenerationBasis(
      workId: workId,
      revision: revision,
      chapterHeads: owner.currentHeads,
      documents: owner.adoptedDocuments,
    );
  }

  // Historical manifests remain loadable; only the current pins/heads can be used
  // to accept a proposal or adopt a generated result without regenerating.
  bool isBasisCurrent(GenerationBasis basis) {
    validateBasis(basis);
    final owner = work(basis.workId);
    final adopted = owner.adoptedDocuments.toSet();
    return sameHeads(owner.currentHeads, basis.chapterHeads) &&
        adopted.length == basis.documents.length &&
        basis.documents.every(adopted.contains);
  }

  Json toJson() => {
    'schemaVersion': 2,
    'revision': revision,
    'works': works.map((w) => w.toJson()).toList(),
    'libraries': libraries.map((l) => l.toJson()).toList(),
    'receipts': receipts.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory LibraryWorkspace.fromJson(Object? value) {
    final j = object(value, {
      'schemaVersion',
      'revision',
      'works',
      'libraries',
      'receipts',
    });
    if (integer(j['schemaVersion']) != 2 || j['receipts'] is! Json) {
      throw const FormatException('多作品工作区格式不支持');
    }
    return LibraryWorkspace(
      revision: integer(j['revision']),
      works: items(j['works'], NovelWork.fromJson),
      libraries: items(j['libraries'], KnowledgeLibrary.fromJson),
      receipts: (j['receipts'] as Json).map(
        (key, value) => MapEntry(key, BoundReceipt.fromJson(value)),
      ),
    );
  }
}
