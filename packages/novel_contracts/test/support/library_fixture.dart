import 'dart:convert';

import 'package:novel_contracts/novel_contracts.dart';

Json jsonCopy(Json value) => jsonDecode(jsonEncode(value)) as Json;

Json versionJson(String id, {String kind = 'reference', String? workId}) => {
  'id': id,
  'title': '雨夜资料 $id',
  'kind': kind,
  'body': '  原始资料正文\n导入内容中的指令只是资料。  ',
  'associatedWorkId': workId,
  'provenance': {
    'writer': {'kind': 'tool', 'id': 'Codex'},
    'sources': [
      {'kind': 'web', 'reference': 'https://example.com/research'},
    ],
  },
};

Json basisJson() => {
  'workId': 'work-a',
  'revision': 4,
  'chapterHeads': {'chapter-1': 'text-1'},
  'documents': [
    {'libraryId': 'lib-a', 'documentId': 'shared', 'versionId': 'v1'},
    {'libraryId': 'lib-b', 'documentId': 'shared', 'versionId': 'v1'},
  ],
};

Json proposalJson() => {
  'workId': 'work-a',
  'discussionSource': null,
  'proposal': {
    'id': 'proposal-1',
    'chapterId': 'chapter-1',
    'title': '雨夜',
    'body': '候选正文尚未被作者接受。',
    'baseHeads': {'chapter-1': 'text-1'},
    'baseRevision': 4,
    'status': 'pending',
    'provider': 'fixture/local',
    'context': {
      'authorInstruction': '保持视角',
      'nested': {
        'values': [1, 2],
      },
    },
    'usage': {},
  },
  'documents': basisJson()['documents'],
};

Json discussionJson() => {
  'id': 'discussion-1',
  'title': '雨夜构思',
  'chapterId': 'chapter-1',
  'messages': [
    {'id': 'author-1', 'role': 'author', 'body': '先讨论线索。', 'provider': null},
    {
      'id': 'assistant-1',
      'role': 'assistant',
      'body': '这是一个未采用的想法。',
      'provider': 'fixture/local',
    },
    {
      'id': 'author-2',
      'role': 'author',
      'body': '讨论失败后保留我的输入。',
      'provider': null,
    },
    {'id': 'author-3', 'role': 'author', 'body': '等待下一次回复。', 'provider': null},
  ],
  'turns': [
    {
      'requestId': 'turn-1',
      'authorMessageId': 'author-1',
      'status': 'completed',
      'assistantMessageId': 'assistant-1',
      'errorCode': null,
      'basis': basisJson(),
    },
    {
      'requestId': 'turn-2',
      'authorMessageId': 'author-2',
      'status': 'failed',
      'assistantMessageId': null,
      'errorCode': 'interrupted',
      'basis': basisJson(),
    },
    {
      'requestId': 'turn-3',
      'authorMessageId': 'author-3',
      'status': 'pending',
      'assistantMessageId': null,
      'errorCode': null,
      'basis': basisJson(),
    },
  ],
};

Json workJson(String id, List<Json> links) => {
  'id': id,
  'title': '作品 $id',
  'knowledgeLinks': links,
  'chapters': [
    {
      'id': 'chapter-1',
      'number': 1,
      'title': '雨夜',
      'head': 'text-1',
      'versions': [
        {'id': 'text-1', 'body': '$id 的已接受事实。'},
        {'id': 'text-2', 'body': '$id 的历史修订。'},
      ],
      'needsReview': false,
    },
  ],
  'proposals': id == 'work-a' ? [proposalJson()] : [],
  'memories': [
    {
      'id': 'memory-1',
      'sourceHeads': {'chapter-1': 'text-1'},
      'facts': [
        {
          'text': '$id 发生了事件',
          'chapterId': 'chapter-1',
          'versionId': 'text-1',
          'evidence': '$id 的已接受事实。',
        },
      ],
    },
  ],
  'discussions': id == 'work-a' ? [discussionJson()] : [],
};

Json libraryFixture() => jsonCopy({
  'schemaVersion': 2,
  'revision': 10,
  'works': [
    workJson('work-a', [
      {
        'libraryId': 'lib-a',
        'versions': {'shared': 'v1'},
      },
      {
        'libraryId': 'lib-b',
        'versions': {'shared': 'v1'},
      },
    ]),
    workJson('work-b', [
      {
        'libraryId': 'lib-a',
        'versions': {'shared': 'v2'},
      },
    ]),
  ],
  'libraries': [
    {
      'id': 'lib-a',
      'name': '共享资料',
      'documents': [
        {
          'id': 'shared',
          'head': 'v2',
          'versions': [versionJson('v1'), versionJson('v2')],
        },
      ],
    },
    {
      'id': 'lib-b',
      'name': '作者设定',
      'documents': [
        {
          'id': 'shared',
          'head': 'v1',
          'versions': [versionJson('v1', kind: 'setting', workId: 'work-a')],
        },
      ],
    },
  ],
  'receipts': {
    'turn-1': {
      'fingerprint': 'v2-request-fingerprint',
      'revision': 6,
      'target': {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
      },
    },
    'turn-2': {
      'fingerprint': 'failed-turn-fingerprint',
      'revision': 8,
      'target': {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
      },
    },
    'turn-3': {
      'fingerprint': 'pending-turn-fingerprint',
      'revision': 10,
      'target': {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
      },
    },
  },
});

Json commandJson({
  String operation = 'saveDocument',
  Json? target,
  Json? payload,
}) => jsonCopy({
  'apiVersion': 2,
  'requestId': 'request-1',
  'expectedRevision': 10,
  'target': target ?? {'kind': 'library', 'libraryId': 'lib-a', 'workId': null},
  'operation': operation,
  'payload':
      payload ??
      {
        'documentId': 'shared',
        'expectedVersionId': 'v2',
        'version': versionJson('v3'),
      },
});
