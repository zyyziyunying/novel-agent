import 'dart:convert';

import 'v2/catalog.dart';
import 'workspace.dart';

/// A work-local domain view, never used as a format 1 storage or HTTP snapshot.
/// Only explicitly adopted document versions enter this view.
extension WorkView on LibraryWorkspace {
  Workspace workView(String workId) {
    final owner = work(workId);
    // Adoption is a set of version pins. UI ordering must not invalidate a
    // proposal when all of its source versions are unchanged.
    final references = [...owner.adoptedDocuments]
      ..sort((a, b) {
        final library = a.libraryId.compareTo(b.libraryId);
        return library != 0 ? library : a.documentId.compareTo(b.documentId);
      });
    return Workspace(
      revision: revision,
      title: owner.title,
      documents: [
        for (final ref in references)
          SourceDocument(
            id: jsonEncode([ref.libraryId, ref.documentId]),
            title: documentVersion(ref).title,
            kind: documentVersion(ref).kind,
            body: documentVersion(ref).body,
          ),
      ],
      chapters: owner.chapters,
      proposals: owner.proposals.map((p) => p.proposal).toList(),
      memories: owner.memories,
      receipts: {
        for (final entry in receipts.entries)
          if (entry.value.target.workId == workId)
            entry.key: Receipt(
              fingerprint: entry.value.fingerprint,
              revision: entry.value.revision,
            ),
      },
    );
  }
}
