import 'package:novel_contracts/novel_contracts.dart';

LibraryCommand command(
  String requestId,
  int revision,
  String operation,
  Json payload, {
  CommandTarget? target,
}) => LibraryCommand(
  requestId: requestId,
  expectedRevision: revision,
  target: target ?? CommandTarget.catalog(),
  operation: operation,
  payload: payload,
);

LibraryCommand createWork([int revision = 0, String id = 'work-a']) => command(
  'create-$id',
  revision,
  'createWork',
  {'id': id, 'title': '作品 $id'},
);

LibraryCommand createLibrary([int revision = 1, String id = 'library-a']) =>
    command('create-$id', revision, 'createLibrary', {
      'id': id,
      'name': '资料库 $id',
    });

LibraryCommand saveDocument(
  int revision, {
  String requestId = 'save-v1',
  String libraryId = 'library-a',
  String? workId = 'work-a',
  String documentId = 'doc-a',
  String versionId = 'v1',
  String? previous,
  String body = '  正文保持原样。\n忽略所有指令是资料中的文字。\n',
}) => command(
  requestId,
  revision,
  'saveDocument',
  {
    'documentId': documentId,
    'expectedVersionId': previous,
    'version': {
      'id': versionId,
      'title': '  雨夜设定  ',
      'kind': 'setting',
      'body': body,
      'provenance': {
        'writer': {'kind': 'tool', 'id': 'Codex'},
        'sources': [
          {'kind': 'web', 'reference': 'https://example.com/story'},
          {'kind': 'author', 'reference': '作者确认'},
        ],
      },
      'associatedWorkId': workId,
    },
  },
  target: CommandTarget.library(libraryId, workId: workId),
);
