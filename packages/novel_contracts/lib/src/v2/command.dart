import 'dart:convert';

import '../workspace.dart';
import 'catalog.dart';
import 'knowledge.dart';
import 'targets.dart';
import 'validation.dart';

const _workOperations = {
  'createChapter',
  'proposeChapter',
  'proposeEdit',
  'saveChapter',
  'restoreVersion',
  'acceptProposal',
  'rejectProposal',
  'rebuildMemory',
  'confirmReview',
};

class LibraryCommand {
  LibraryCommand({
    required this.requestId,
    required this.expectedRevision,
    required this.target,
    required this.operation,
    required Json payload,
  }) : payload = immutableJson(payload) as Json {
    identifier(requestId);
    integer(expectedRevision);
    _validatePayload();
  }
  final String requestId;
  final int expectedRevision;
  final CommandTarget target;
  final String operation;
  final Json payload;

  void _requireTarget(String kind) {
    if (target.kind != kind) throw const FormatException('操作与请求目标不匹配');
  }

  void _validatePayload() {
    if (_workOperations.contains(operation)) {
      _requireTarget('work');
      NovelCommand(
        requestId: requestId,
        expectedRevision: expectedRevision,
        operation: operation,
        payload: payload,
      );
      for (final key in payload.keys.where((k) => k.endsWith('Id'))) {
        identifier(payload[key]);
      }
      if (operation == 'proposeEdit' && payload['start'] >= payload['end']) {
        throw const FormatException('选段必须是非空范围');
      }
      return;
    }
    switch (operation) {
      case 'createWork':
        _requireTarget('catalog');
        object(payload, {'id', 'title'});
        identifier(payload['id']);
        readText(payload['title']);
      case 'createLibrary':
        _requireTarget('catalog');
        object(payload, {'id', 'name'});
        identifier(payload['id']);
        readText(payload['name']);
      case 'renameWork':
        _requireTarget('work');
        object(payload, {'title'});
        readText(payload['title']);
      case 'renameLibrary':
        _requireTarget('library');
        if (target.workId != null) throw const FormatException('知识库命名不指定作品关联');
        object(payload, {'name'});
        readText(payload['name']);
      case 'setKnowledgeLinks':
        _requireTarget('work');
        object(payload, {'links'});
        final links = items(payload['links'], LibraryLink.fromJson);
        uniqueIds(links.map((l) => l.libraryId));
      case 'saveDocument':
        _requireTarget('library');
        _validateDocument({'documentId', 'expectedVersionId', 'version'});
      case 'createDiscussion':
        _requireTarget('work');
        object(payload, {'id', 'title', 'chapterId'});
        identifier(payload['id']);
        readText(payload['title']);
        optionalIdentifier(payload['chapterId']);
      case 'sendDiscussionMessage':
        _requireTarget('discussion');
        object(payload, {'messageId', 'body'});
        identifier(payload['messageId']);
        readText(payload['body']);
      case 'adoptDiscussionMessage':
        if (target.kind == 'library') {
          final version = _validateDocument({
            'source',
            'documentId',
            'expectedVersionId',
            'version',
          });
          final source = DiscussionSource.fromJson(payload['source']);
          if (!version.provenance.sources.whereType<DiscussionSource>().any(
            (s) =>
                s.workId == source.workId &&
                s.discussionId == source.discussionId &&
                s.messageId == source.messageId,
          )) {
            throw const FormatException('讨论成果必须保留所选消息来源');
          }
        } else {
          _requireTarget('work');
          object(payload, {'source', 'proposal'});
          final source = DiscussionSource.fromJson(payload['source']);
          final proposal = WorkProposal.fromJson(payload['proposal']);
          final recorded = proposal.discussionSource;
          if (source.workId != target.workId ||
              proposal.workId != target.workId ||
              proposal.proposal.status != 'pending' ||
              recorded == null ||
              recorded.workId != source.workId ||
              recorded.discussionId != source.discussionId ||
              recorded.messageId != source.messageId) {
            throw const FormatException('正文提案只能采用同作品讨论');
          }
        }
      default:
        throw const FormatException('未知操作');
    }
  }

  KnowledgeVersion _validateDocument(Set<String> fields) {
    object(payload, fields);
    identifier(payload['documentId']);
    final previous = optionalIdentifier(payload['expectedVersionId']);
    final version = KnowledgeVersion.fromJson(payload['version']);
    if (previous == version.id || version.associatedWorkId != target.workId) {
      throw const FormatException('新资料版本或作品关联与请求不一致');
    }
    return version;
  }

  Json toJson() => {
    'apiVersion': 2,
    'requestId': requestId,
    'expectedRevision': expectedRevision,
    'target': target.toJson(),
    'operation': operation,
    'payload': payload,
  };
  String get canonical => jsonEncode(sortedJson(toJson()));
  factory LibraryCommand.fromJson(Object? value) {
    final j = object(value, {
      'apiVersion',
      'requestId',
      'expectedRevision',
      'target',
      'operation',
      'payload',
    });
    if (integer(j['apiVersion']) != 2 || j['payload'] is! Json) {
      throw const FormatException('请求协议版本或数据无效');
    }
    return LibraryCommand(
      requestId: identifier(j['requestId']),
      expectedRevision: integer(j['expectedRevision']),
      target: CommandTarget.fromJson(j['target']),
      operation: readText(j['operation']),
      payload: j['payload'],
    );
  }
}
