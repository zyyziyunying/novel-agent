import 'dart:convert';

import 'library.dart';
import 'workspace.dart';

String knowledgeKey(DocumentReference ref) =>
    jsonEncode([ref.libraryId, ref.documentId, ref.versionId]);

/// A routing description, never a replacement for the original source text.
Json knowledgeCatalogEntry(DocumentReference ref, KnowledgeVersion version) => {
  ...ref.toJson(),
  'key': knowledgeKey(ref),
  'title': version.title,
  'kind': version.kind,
  'description': version.description,
  'tags': version.tags,
  'alwaysRead': version.alwaysRead,
  'requiresFullText': version.requiresFullText,
};

List<Json> knowledgeCatalog(
  LibraryWorkspace workspace,
  GenerationBasis basis,
) => [
  for (final ref in basis.documents)
    knowledgeCatalogEntry(ref, workspace.documentVersion(ref)),
]..sort((a, b) => (a['key'] as String).compareTo(b['key'] as String));
