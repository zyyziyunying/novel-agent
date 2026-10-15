import '../workspace.dart';
import 'knowledge.dart';
import 'validation.dart';

class GenerationBasis {
  GenerationBasis({
    required this.workId,
    required this.revision,
    required Map<String, String> chapterHeads,
    required List<DocumentReference> documents,
  }) : chapterHeads = versionMap(chapterHeads),
       documents = List.unmodifiable(documents) {
    identifier(workId);
    integer(revision);
    if (documents.map((d) => (d.libraryId, d.documentId)).toSet().length !=
        documents.length) {
      throw const FormatException('同一上下文不可引用一份资料的多个版本');
    }
  }
  final String workId;
  final int revision;
  final Map<String, String> chapterHeads;
  final List<DocumentReference> documents;
  Json toJson() => {
    'workId': workId,
    'revision': revision,
    'chapterHeads': chapterHeads,
    'documents': documents.map((d) => d.toJson()).toList(),
  };
  factory GenerationBasis.fromJson(Object? value) {
    final j = object(value, {
      'workId',
      'revision',
      'chapterHeads',
      'documents',
    });
    return GenerationBasis(
      workId: identifier(j['workId']),
      revision: integer(j['revision']),
      chapterHeads: versionMap(j['chapterHeads']),
      documents: items(j['documents'], DocumentReference.fromJson),
    );
  }
}

class DiscussionMessage {
  DiscussionMessage({
    required this.id,
    required this.role,
    required this.body,
    required this.provider,
  }) {
    identifier(id);
    choice(role, {'author', 'assistant'});
    readText(body);
    if (role == 'author') {
      if (provider != null) {
        throw const FormatException('作者消息不声明模型提供方');
      }
    } else if (provider == null) {
      throw const FormatException('模型消息必须保留提供方');
    } else {
      readText(provider);
    }
  }
  final String id;
  final String role;
  final String body;
  final String? provider;
  Json toJson() => {'id': id, 'role': role, 'body': body, 'provider': provider};
  factory DiscussionMessage.fromJson(Object? value) {
    final j = object(value, {'id', 'role', 'body', 'provider'});
    return DiscussionMessage(
      id: identifier(j['id']),
      role: readText(j['role']),
      body: readText(j['body']),
      provider: j['provider'] == null ? null : readText(j['provider']),
    );
  }
}

class DiscussionTurn {
  DiscussionTurn({
    required this.requestId,
    required this.authorMessageId,
    required this.status,
    required this.assistantMessageId,
    required this.errorCode,
    required this.basis,
    List<DocumentReference>? readDocuments,
  }) : readDocuments = readDocuments == null
           ? null
           : List.unmodifiable(readDocuments) {
    identifier(requestId);
    identifier(authorMessageId);
    choice(status, {'pending', 'completed', 'failed'});
    optionalIdentifier(assistantMessageId);
    if (readDocuments != null &&
        (readDocuments.toSet().length != readDocuments.length ||
            !readDocuments.every(basis.documents.contains))) {
      throw const FormatException('实际读取资料必须属于本轮固定来源且不能重复');
    }
    if (errorCode != null) {
      choice(errorCode, {
        'model_unavailable',
        'model_failed',
        'version_conflict',
        'interrupted',
      });
    }
    if ((status == 'completed') != (assistantMessageId != null) ||
        (status == 'failed') != (errorCode != null)) {
      throw const FormatException('讨论轮次状态不一致');
    }
  }
  final String requestId;
  final String authorMessageId;
  final String status;
  final String? assistantMessageId;
  final String? errorCode;
  // Captured before invoking the model; also retained for pending/failed turns.
  final GenerationBasis basis;
  // Missing in historical turns. Non-null also pins selection across retries.
  final List<DocumentReference>? readDocuments;
  Json toJson() => {
    'requestId': requestId,
    'authorMessageId': authorMessageId,
    'status': status,
    'assistantMessageId': assistantMessageId,
    'errorCode': errorCode,
    'basis': basis.toJson(),
    if (readDocuments != null)
      'readDocuments': readDocuments!.map((ref) => ref.toJson()).toList(),
  };
  factory DiscussionTurn.fromJson(Object? value) {
    final j = objectWithOptional(
      value,
      {
        'requestId',
        'authorMessageId',
        'status',
        'assistantMessageId',
        'errorCode',
        'basis',
      },
      {'readDocuments'},
    );
    return DiscussionTurn(
      requestId: identifier(j['requestId']),
      authorMessageId: identifier(j['authorMessageId']),
      status: readText(j['status']),
      assistantMessageId: optionalIdentifier(j['assistantMessageId']),
      errorCode: j['errorCode'] == null ? null : readText(j['errorCode']),
      basis: GenerationBasis.fromJson(j['basis']),
      readDocuments: j.containsKey('readDocuments')
          ? items(j['readDocuments'], DocumentReference.fromJson)
          : null,
    );
  }
}

class Discussion {
  Discussion({
    required this.id,
    required this.title,
    required this.chapterId,
    required List<DiscussionMessage> messages,
    required List<DiscussionTurn> turns,
  }) : messages = List.unmodifiable(messages),
       turns = List.unmodifiable(turns) {
    identifier(id);
    readText(title);
    optionalIdentifier(chapterId);
    uniqueIds(messages.map((m) => m.id));
    uniqueIds(turns.map((t) => t.requestId));
    final used = <String>{};
    for (final turn in turns) {
      final author = messages.indexWhere((m) => m.id == turn.authorMessageId);
      if (author < 0 ||
          messages[author].role != 'author' ||
          !used.add(turn.authorMessageId)) {
        throw const FormatException('讨论轮次的作者消息无效');
      }
      if (turn.assistantMessageId != null) {
        final assistant = messages.indexWhere(
          (m) => m.id == turn.assistantMessageId,
        );
        if (assistant <= author ||
            messages[assistant].role != 'assistant' ||
            !used.add(turn.assistantMessageId!)) {
          throw const FormatException('讨论轮次的模型消息无效');
        }
      }
    }
    if (used.length != messages.length) {
      throw const FormatException('讨论消息必须属于一个轮次');
    }
  }
  final String id;
  final String title;
  final String? chapterId;
  final List<DiscussionMessage> messages;
  final List<DiscussionTurn> turns;
  Json toJson() => {
    'id': id,
    'title': title,
    'chapterId': chapterId,
    'messages': messages.map((m) => m.toJson()).toList(),
    'turns': turns.map((t) => t.toJson()).toList(),
  };
  factory Discussion.fromJson(Object? value) {
    final j = object(value, {'id', 'title', 'chapterId', 'messages', 'turns'});
    return Discussion(
      id: identifier(j['id']),
      title: readText(j['title']),
      chapterId: optionalIdentifier(j['chapterId']),
      messages: items(j['messages'], DiscussionMessage.fromJson),
      turns: items(j['turns'], DiscussionTurn.fromJson),
    );
  }
}
