import 'dart:convert';

import 'package:novel_contracts/novel_contracts.dart';

class KnowledgeSelection {
  KnowledgeSelection(this.keys, {this.usage = const {}});
  final List<String> keys;
  final Json usage;
}

abstract interface class KnowledgeSelector {
  Future<KnowledgeSelection> selectKnowledge(
    Json directory,
    String instruction,
  );
}

class PreparedKnowledge {
  PreparedKnowledge(this.context, this.references, this.usage);
  final Json context;
  final List<DocumentReference> references;
  final Json usage;
}

List<Json> catalogFromContext(Json context) => [
  for (final entry in context['knowledgeDocuments'] as List? ?? [])
    knowledgeCatalogEntry(
      DocumentReference.fromJson({
        'libraryId': entry['libraryId'],
        'documentId': entry['documentId'],
        'versionId': entry['versionId'],
      }),
      KnowledgeVersion.fromJson(entry['version']),
    ),
]..sort((a, b) => (a['key'] as String).compareTo(b['key'] as String));

/// Only the directory and task reach the selector. Full texts stay in the host
/// until a validated selection is made from this request's adopted versions.
Future<PreparedKnowledge> prepareKnowledge(
  Object model,
  Json source,
  String instruction, {
  required String task,
}) async {
  // The independent format 1 prototype retains its original behavior.
  if (!source.containsKey('knowledgeDocuments')) {
    return PreparedKnowledge(source, [], {});
  }
  final catalog = catalogFromContext(source);
  final selected = <String>{
    for (final entry in catalog)
      if (entry['requiresFullText'] as bool) entry['key'] as String,
  };
  Json usage = {};
  if (catalog.any((entry) => !(entry['requiresFullText'] as bool))) {
    if (model is! KnowledgeSelector) {
      throw const FormatException('当前模型未提供资料选择能力');
    }
    final choice = await model.selectKnowledge({
      'task': task,
      'knowledgeCatalog': catalog,
      if (source['selection'] != null) 'selection': source['selection'],
      if (source['discussionMessages'] != null)
        'discussionMessages': source['discussionMessages'],
      'chapters': [
        for (final chapter in source['acceptedChapters'] as List? ?? [])
          {'number': chapter['number'], 'title': chapter['title']},
      ],
    }, instruction);
    final allowed = catalog.map((entry) => entry['key']).toSet();
    if (choice.keys.toSet().length != choice.keys.length ||
        !choice.keys.every(allowed.contains)) {
      throw const FormatException('模型选择了目录外或重复的资料');
    }
    selected.addAll(choice.keys);
    usage = choice.usage;
  }
  final manifest = <Json>[
    for (final entry in source['knowledgeDocuments'] as List)
      if (selected.contains(
        jsonEncode([
          entry['libraryId'],
          entry['documentId'],
          entry['versionId'],
        ]),
      ))
        Map<String, dynamic>.from(entry as Map),
  ];
  final refs = [
    for (final entry in manifest)
      DocumentReference.fromJson({
        'libraryId': entry['libraryId'],
        'documentId': entry['documentId'],
        'versionId': entry['versionId'],
      }),
  ];
  return PreparedKnowledge(
    {
      ...source,
      'knowledgeCatalog': catalog,
      'readDocuments': refs.map((ref) => ref.toJson()).toList(),
      'knowledgeDocuments': manifest,
      'documents': [
        for (final entry in manifest)
          SourceDocument(
            id: jsonEncode([entry['libraryId'], entry['documentId']]),
            title: entry['version']['title'],
            kind: entry['version']['kind'],
            body: entry['version']['body'],
          ).toJson(),
      ],
    },
    refs,
    usage,
  );
}
