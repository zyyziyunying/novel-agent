import '../workspace.dart';
import 'validation.dart';

class DocumentReference {
  DocumentReference({
    required this.libraryId,
    required this.documentId,
    required this.versionId,
  }) {
    identifier(libraryId);
    identifier(documentId);
    identifier(versionId);
  }
  final String libraryId;
  final String documentId;
  final String versionId;
  Json toJson() => {
    'libraryId': libraryId,
    'documentId': documentId,
    'versionId': versionId,
  };
  factory DocumentReference.fromJson(Object? value) {
    final j = object(value, {'libraryId', 'documentId', 'versionId'});
    return DocumentReference(
      libraryId: identifier(j['libraryId']),
      documentId: identifier(j['documentId']),
      versionId: identifier(j['versionId']),
    );
  }
  @override
  bool operator ==(Object other) =>
      other is DocumentReference &&
      libraryId == other.libraryId &&
      documentId == other.documentId &&
      versionId == other.versionId;
  @override
  int get hashCode => Object.hash(libraryId, documentId, versionId);
}

class SourceWriter {
  SourceWriter({required this.kind, required this.id}) {
    choice(kind, {'author', 'tool', 'import'});
    identifier(id);
  }
  final String kind;
  final String id;
  Json toJson() => {'kind': kind, 'id': id};
  factory SourceWriter.fromJson(Object? value) {
    final j = object(value, {'kind', 'id'});
    return SourceWriter(kind: readText(j['kind']), id: identifier(j['id']));
  }
}

sealed class OriginalSource {
  Json toJson();
  factory OriginalSource.fromJson(Object? value) {
    if (value is! Json) throw const FormatException('资料来源无效');
    return value['kind'] == 'discussion'
        ? DiscussionSource.fromJson(value)
        : ExternalSource.fromJson(value);
  }
  OriginalSource();
}

class ExternalSource extends OriginalSource {
  ExternalSource({required this.kind, required this.reference}) {
    choice(kind, {'web', 'file', 'author'});
    readText(reference);
    if (kind == 'web') {
      final uri = Uri.tryParse(reference);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('网页来源需要 HTTP(S) 地址');
      }
    }
  }
  final String kind;
  final String reference;
  @override
  Json toJson() => {'kind': kind, 'reference': reference};
  factory ExternalSource.fromJson(Object? value) {
    final j = object(value, {'kind', 'reference'});
    return ExternalSource(
      kind: readText(j['kind']),
      reference: readText(j['reference']),
    );
  }
}

class DiscussionSource extends OriginalSource {
  DiscussionSource({
    required this.workId,
    required this.discussionId,
    required this.messageId,
  }) {
    identifier(workId);
    identifier(discussionId);
    identifier(messageId);
  }
  final String workId;
  final String discussionId;
  final String messageId;
  @override
  Json toJson() => {
    'kind': 'discussion',
    'workId': workId,
    'discussionId': discussionId,
    'messageId': messageId,
  };
  factory DiscussionSource.fromJson(Object? value) {
    final j = object(value, {'kind', 'workId', 'discussionId', 'messageId'});
    choice(j['kind'], {'discussion'});
    return DiscussionSource(
      workId: identifier(j['workId']),
      discussionId: identifier(j['discussionId']),
      messageId: identifier(j['messageId']),
    );
  }
}

class SourceProvenance {
  SourceProvenance({
    required this.writer,
    required List<OriginalSource> sources,
  }) : sources = List.unmodifiable(sources) {
    if (sources.isEmpty) throw const FormatException('资料必须保留原始来源');
  }
  final SourceWriter writer;
  final List<OriginalSource> sources;
  Json toJson() => {
    'writer': writer.toJson(),
    'sources': sources.map((s) => s.toJson()).toList(),
  };
  factory SourceProvenance.fromJson(Object? value) {
    final j = object(value, {'writer', 'sources'});
    return SourceProvenance(
      writer: SourceWriter.fromJson(j['writer']),
      sources: items(j['sources'], OriginalSource.fromJson),
    );
  }
}

class KnowledgeVersion {
  KnowledgeVersion({
    required this.id,
    required this.title,
    required this.kind,
    required this.body,
    required this.provenance,
    required this.associatedWorkId,
    this.description = '',
    List<String> tags = const [],
    this.alwaysRead = false,
  }) : tags = List.unmodifiable(tags) {
    identifier(id);
    readText(title);
    choice(kind, {'setting', 'reference', 'plan'});
    readText(body);
    optionalIdentifier(associatedWorkId);
    if (description.length > 500 || tags.length > 20) {
      throw const FormatException('简介最多 500 字符，标签最多 20 个');
    }
    if (tags.any(
          (tag) =>
              tag.trim().isEmpty ||
              tag != tag.trim() ||
              tag.length > 40 ||
              RegExp(r'[,，\r\n]').hasMatch(tag),
        ) ||
        tags.toSet().length != tags.length) {
      throw const FormatException('标签须为不重复的短文本，每个最多 40 字符，不能包含逗号或换行');
    }
  }
  final String id;
  final String title;
  final String kind;
  final String body;
  final String description;
  final List<String> tags;
  final bool alwaysRead;
  // Old versions lack a description: preserve their full-context behavior.
  bool get requiresFullText => alwaysRead || description.trim().isEmpty;
  final SourceProvenance provenance;
  // Attribution only; association does not adopt the content for a work.
  final String? associatedWorkId;
  Json toJson() => {
    'id': id,
    'title': title,
    'kind': kind,
    'body': body,
    'provenance': provenance.toJson(),
    'associatedWorkId': associatedWorkId,
    if (description.isNotEmpty) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
    if (alwaysRead) 'alwaysRead': true,
  };
  factory KnowledgeVersion.fromJson(Object? value) {
    final j = objectWithOptional(
      value,
      {'id', 'title', 'kind', 'body', 'provenance', 'associatedWorkId'},
      {'description', 'tags', 'alwaysRead'},
    );
    if (j.containsKey('alwaysRead') && j['alwaysRead'] is! bool) {
      throw const FormatException('必读设置必须为布尔值');
    }
    return KnowledgeVersion(
      id: identifier(j['id']),
      title: readText(j['title']),
      kind: readText(j['kind']),
      body: readText(j['body']),
      provenance: SourceProvenance.fromJson(j['provenance']),
      associatedWorkId: optionalIdentifier(j['associatedWorkId']),
      description: j.containsKey('description')
          ? readText(j['description'], allowEmpty: true)
          : '',
      tags: j.containsKey('tags') ? items(j['tags'], readText) : [],
      alwaysRead: j.containsKey('alwaysRead') ? j['alwaysRead'] as bool : false,
    );
  }
}

class KnowledgeDocument {
  KnowledgeDocument({
    required this.id,
    required this.head,
    required List<KnowledgeVersion> versions,
  }) : versions = List.unmodifiable(versions) {
    identifier(id);
    identifier(head);
    uniqueIds(versions.map((v) => v.id));
    if (!versions.any((v) => v.id == head)) {
      throw const FormatException('资料当前版本不存在');
    }
  }
  final String id;
  final String head;
  final List<KnowledgeVersion> versions;
  KnowledgeVersion get current => versions.firstWhere((v) => v.id == head);
  Json toJson() => {
    'id': id,
    'head': head,
    'versions': versions.map((v) => v.toJson()).toList(),
  };
  factory KnowledgeDocument.fromJson(Object? value) {
    final j = object(value, {'id', 'head', 'versions'});
    return KnowledgeDocument(
      id: identifier(j['id']),
      head: identifier(j['head']),
      versions: items(j['versions'], KnowledgeVersion.fromJson),
    );
  }
}

class KnowledgeLibrary {
  KnowledgeLibrary({
    required this.id,
    required this.name,
    required List<KnowledgeDocument> documents,
  }) : documents = List.unmodifiable(documents) {
    identifier(id);
    readText(name);
    uniqueIds(documents.map((d) => d.id));
  }
  final String id;
  final String name;
  final List<KnowledgeDocument> documents;
  Json toJson() => {
    'id': id,
    'name': name,
    'documents': documents.map((d) => d.toJson()).toList(),
  };
  factory KnowledgeLibrary.fromJson(Object? value) {
    final j = object(value, {'id', 'name', 'documents'});
    return KnowledgeLibrary(
      id: identifier(j['id']),
      name: readText(j['name']),
      documents: items(j['documents'], KnowledgeDocument.fromJson),
    );
  }
}

class LibraryLink {
  LibraryLink({required this.libraryId, required Map<String, String> versions})
    : versions = versionMap(versions) {
    identifier(libraryId);
  }
  final String libraryId;
  // Whole-document version pins, including identity, title, content and sources.
  final Map<String, String> versions;
  List<DocumentReference> get references => [
    for (final entry in versions.entries)
      DocumentReference(
        libraryId: libraryId,
        documentId: entry.key,
        versionId: entry.value,
      ),
  ];
  Json toJson() => {'libraryId': libraryId, 'versions': versions};
  factory LibraryLink.fromJson(Object? value) {
    final j = object(value, {'libraryId', 'versions'});
    return LibraryLink(
      libraryId: identifier(j['libraryId']),
      versions: versionMap(j['versions']),
    );
  }
}
