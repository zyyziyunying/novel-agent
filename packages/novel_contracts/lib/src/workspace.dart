import 'dart:convert';

typedef Json = Map<String, dynamic>;

Json object(Object? value, Set<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.keys.any((key) => !fields.contains(key)) ||
      fields.any((key) => !value.containsKey(key))) {
    throw const FormatException('JSON 字段不符合契约');
  }
  return value;
}

String readText(Object? value, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('需要文本');
  }
  return value;
}

int integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum) {
    throw const FormatException('需要整数');
  }
  return value;
}

List<T> items<T>(Object? value, T Function(Object?) parse) {
  if (value is! List) throw const FormatException('需要列表');
  return List.unmodifiable(value.map(parse));
}

Map<String, String> heads(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('需要版本映射');
  }
  return Map.unmodifiable(value.map((k, v) => MapEntry(k, readText(v))));
}

bool sameHeads(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

class SourceDocument {
  SourceDocument({
    required this.id,
    required this.title,
    required this.kind,
    required this.body,
  }) {
    if (!{'setting', 'reference', 'plan'}.contains(kind)) {
      throw const FormatException('未知资料身份');
    }
  }
  final String id;
  final String title;
  final String kind;
  final String body;
  Json toJson() => {'id': id, 'title': title, 'kind': kind, 'body': body};
  factory SourceDocument.fromJson(Object? value) {
    final j = object(value, {'id', 'title', 'kind', 'body'});
    return SourceDocument(
      id: readText(j['id']),
      title: readText(j['title']),
      kind: readText(j['kind']),
      body: readText(j['body']),
    );
  }
}

class TextVersion {
  const TextVersion({required this.id, required this.body});
  final String id;
  final String body;
  Json toJson() => {'id': id, 'body': body};
  factory TextVersion.fromJson(Object? value) {
    final j = object(value, {'id', 'body'});
    return TextVersion(id: readText(j['id']), body: readText(j['body']));
  }
}

class Chapter {
  Chapter({
    required this.id,
    required this.number,
    required this.title,
    required this.head,
    required List<TextVersion> versions,
    this.needsReview = false,
  }) : versions = List.unmodifiable(versions) {
    if (number < 1 ||
        versions.isEmpty ||
        versions.map((v) => v.id).toSet().length != versions.length ||
        !versions.any((v) => v.id == head)) {
      throw const FormatException('章节版本无效');
    }
  }
  final String id;
  final int number;
  final String title;
  final String head;
  final List<TextVersion> versions;
  final bool needsReview;
  String get body => versions.firstWhere((v) => v.id == head).body;
  Chapter replace({
    String? head,
    List<TextVersion>? versions,
    bool? needsReview,
  }) => Chapter(
    id: id,
    number: number,
    title: title,
    head: head ?? this.head,
    versions: versions ?? this.versions,
    needsReview: needsReview ?? this.needsReview,
  );
  Json toJson() => {
    'id': id,
    'number': number,
    'title': title,
    'head': head,
    'versions': versions.map((v) => v.toJson()).toList(),
    'needsReview': needsReview,
  };
  factory Chapter.fromJson(Object? value) {
    final j = object(value, {
      'id',
      'number',
      'title',
      'head',
      'versions',
      'needsReview',
    });
    if (j['needsReview'] is! bool) throw const FormatException('需要布尔值');
    return Chapter(
      id: readText(j['id']),
      number: integer(j['number'], minimum: 1),
      title: readText(j['title']),
      head: readText(j['head']),
      versions: items(j['versions'], TextVersion.fromJson),
      needsReview: j['needsReview'],
    );
  }
}

class StoryFact {
  const StoryFact({
    required this.text,
    required this.chapterId,
    required this.versionId,
    required this.evidence,
  });
  final String text;
  final String chapterId;
  final String versionId;
  final String evidence;
  Json toJson() => {
    'text': text,
    'chapterId': chapterId,
    'versionId': versionId,
    'evidence': evidence,
  };
  factory StoryFact.fromJson(Object? value) {
    final j = object(value, {'text', 'chapterId', 'versionId', 'evidence'});
    return StoryFact(
      text: readText(j['text']),
      chapterId: readText(j['chapterId']),
      versionId: readText(j['versionId']),
      evidence: readText(j['evidence']),
    );
  }
}

class MemorySnapshot {
  MemorySnapshot({
    required this.id,
    required Map<String, String> sourceHeads,
    required List<StoryFact> facts,
  }) : sourceHeads = Map.unmodifiable(sourceHeads),
       facts = List.unmodifiable(facts);
  final String id;
  final Map<String, String> sourceHeads;
  final List<StoryFact> facts;
  Json toJson() => {
    'id': id,
    'sourceHeads': sourceHeads,
    'facts': facts.map((f) => f.toJson()).toList(),
  };
  factory MemorySnapshot.fromJson(Object? value) {
    final j = object(value, {'id', 'sourceHeads', 'facts'});
    return MemorySnapshot(
      id: readText(j['id']),
      sourceHeads: heads(j['sourceHeads']),
      facts: items(j['facts'], StoryFact.fromJson),
    );
  }
}

class Proposal {
  Proposal({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.body,
    required Map<String, String> baseHeads,
    required this.baseRevision,
    required this.status,
    required this.provider,
    required Json context,
    required Json usage,
  }) : baseHeads = Map.unmodifiable(baseHeads),
       context = Map.unmodifiable(context),
       usage = Map.unmodifiable(usage) {
    if (!{'pending', 'accepted', 'rejected'}.contains(status)) {
      throw const FormatException('未知提案状态');
    }
  }
  final String id;
  final String chapterId;
  final String title;
  final String body;
  final Map<String, String> baseHeads;
  final int baseRevision;
  final String status;
  final String provider;
  final Json context;
  final Json usage;
  Proposal decide(String status) => Proposal(
    id: id,
    chapterId: chapterId,
    title: title,
    body: body,
    baseHeads: baseHeads,
    baseRevision: baseRevision,
    status: status,
    provider: provider,
    context: context,
    usage: usage,
  );
  Json toJson() => {
    'id': id,
    'chapterId': chapterId,
    'title': title,
    'body': body,
    'baseHeads': baseHeads,
    'baseRevision': baseRevision,
    'status': status,
    'provider': provider,
    'context': context,
    'usage': usage,
  };
  factory Proposal.fromJson(Object? value) {
    final j = object(value, {
      'id',
      'chapterId',
      'title',
      'body',
      'baseHeads',
      'baseRevision',
      'status',
      'provider',
      'context',
      'usage',
    });
    if (j['context'] is! Json || j['usage'] is! Json) {
      throw const FormatException('提案上下文无效');
    }
    return Proposal(
      id: readText(j['id']),
      chapterId: readText(j['chapterId']),
      title: readText(j['title']),
      body: readText(j['body']),
      baseHeads: heads(j['baseHeads']),
      baseRevision: integer(j['baseRevision']),
      status: readText(j['status']),
      provider: readText(j['provider']),
      context: j['context'],
      usage: j['usage'],
    );
  }
}

class Receipt {
  const Receipt({required this.fingerprint, required this.revision});
  final String fingerprint;
  final int revision;
  Json toJson() => {'fingerprint': fingerprint, 'revision': revision};
  factory Receipt.fromJson(Object? value) {
    final j = object(value, {'fingerprint', 'revision'});
    return Receipt(
      fingerprint: readText(j['fingerprint']),
      revision: integer(j['revision']),
    );
  }
}

class Workspace {
  Workspace({
    required this.revision,
    required this.title,
    required List<SourceDocument> documents,
    required List<Chapter> chapters,
    required List<Proposal> proposals,
    required List<MemorySnapshot> memories,
    required Map<String, Receipt> receipts,
  }) : documents = List.unmodifiable(documents),
       chapters = List.unmodifiable(chapters),
       proposals = List.unmodifiable(proposals),
       memories = List.unmodifiable(memories),
       receipts = Map.unmodifiable(receipts) {
    if (revision < 0 ||
        chapters.map((c) => c.id).toSet().length != chapters.length ||
        documents.map((d) => d.id).toSet().length != documents.length ||
        proposals.map((p) => p.id).toSet().length != proposals.length) {
      throw const FormatException('工作区标识无效');
    }
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].number != i + 1) throw const FormatException('章节顺序无效');
    }
    for (final memory in memories) {
      if (memory.sourceHeads.length > chapters.length) {
        throw const FormatException('记忆来源无效');
      }
      for (final entry in memory.sourceHeads.entries) {
        final chapter = chapters.where((c) => c.id == entry.key).firstOrNull;
        if (chapter == null ||
            !chapter.versions.any((v) => v.id == entry.value)) {
          throw const FormatException('记忆来源版本不存在');
        }
      }
      for (final fact in memory.facts) {
        final chapter = chapters
            .where((c) => c.id == fact.chapterId)
            .firstOrNull;
        final version = chapter?.versions
            .where((v) => v.id == fact.versionId)
            .firstOrNull;
        if (version == null ||
            memory.sourceHeads[fact.chapterId] != fact.versionId ||
            fact.evidence.isEmpty ||
            !version.body.contains(fact.evidence)) {
          throw const FormatException('记忆证据无效');
        }
      }
    }
  }
  final int revision;
  final String title;
  final List<SourceDocument> documents;
  final List<Chapter> chapters;
  final List<Proposal> proposals;
  final List<MemorySnapshot> memories;
  final Map<String, Receipt> receipts;
  Map<String, String> get currentHeads => {
    for (final c in chapters) c.id: c.head,
  };
  MemorySnapshot? get currentMemory => memories.reversed
      .where((m) => sameHeads(m.sourceHeads, currentHeads))
      .firstOrNull;
  bool get memoryFresh => chapters.isEmpty || currentMemory != null;
  Workspace replace({
    int? revision,
    List<SourceDocument>? documents,
    List<Chapter>? chapters,
    List<Proposal>? proposals,
    List<MemorySnapshot>? memories,
    Map<String, Receipt>? receipts,
  }) => Workspace(
    revision: revision ?? this.revision,
    title: title,
    documents: documents ?? this.documents,
    chapters: chapters ?? this.chapters,
    proposals: proposals ?? this.proposals,
    memories: memories ?? this.memories,
    receipts: receipts ?? this.receipts,
  );
  Json toJson() => {
    'schemaVersion': 1,
    'revision': revision,
    'title': title,
    'documents': documents.map((d) => d.toJson()).toList(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
    'memories': memories.map((m) => m.toJson()).toList(),
    'receipts': receipts.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory Workspace.fromJson(Object? value) {
    final j = object(value, {
      'schemaVersion',
      'revision',
      'title',
      'documents',
      'chapters',
      'proposals',
      'memories',
      'receipts',
    });
    if (j['schemaVersion'] != 1 || j['receipts'] is! Json) {
      throw const FormatException('工作区格式不支持');
    }
    return Workspace(
      revision: integer(j['revision']),
      title: readText(j['title']),
      documents: items(j['documents'], SourceDocument.fromJson),
      chapters: items(j['chapters'], Chapter.fromJson),
      proposals: items(j['proposals'], Proposal.fromJson),
      memories: items(j['memories'], MemorySnapshot.fromJson),
      receipts: (j['receipts'] as Json).map(
        (k, v) => MapEntry(k, Receipt.fromJson(v)),
      ),
    );
  }
}

class NovelCommand {
  NovelCommand({
    required this.requestId,
    required this.expectedRevision,
    required this.operation,
    required Json payload,
  }) : payload = Map.unmodifiable(payload) {
    readText(requestId);
    integer(expectedRevision);
    final fields = switch (operation) {
      'proposeChapter' => {'instruction'},
      'proposeEdit' => {'chapterId', 'start', 'end', 'instruction'},
      'saveChapter' => {'chapterId', 'body'},
      'restoreVersion' => {'chapterId', 'versionId'},
      'acceptProposal' || 'rejectProposal' => {'proposalId'},
      'rebuildMemory' => <String>{},
      'saveDocument' => {'id', 'title', 'kind', 'body'},
      'confirmReview' => {'chapterId'},
      _ => throw const FormatException('未知操作'),
    };
    object(payload, fields);
    for (final key in fields) {
      if (key == 'start' || key == 'end') {
        integer(payload[key]);
      } else {
        readText(payload[key]);
      }
    }
  }
  final String requestId;
  final int expectedRevision;
  final String operation;
  final Json payload;
  Json toJson() => {
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'operation': operation,
    'payload': payload,
  };
  String get canonical => jsonEncode({
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'operation': operation,
    'payload': {for (final k in payload.keys.toList()..sort()) k: payload[k]},
  });
  factory NovelCommand.fromJson(Object? value) {
    final j = object(value, {
      'requestId',
      'expectedRevision',
      'operation',
      'payload',
    });
    if (j['payload'] is! Json) throw const FormatException('操作数据无效');
    return NovelCommand(
      requestId: readText(j['requestId']),
      expectedRevision: integer(j['expectedRevision']),
      operation: readText(j['operation']),
      payload: j['payload'],
    );
  }
}
