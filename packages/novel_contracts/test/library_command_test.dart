import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_fixture.dart';

void main() {
  group('请求目标与内容', () {
    test('新增明确使用 null 旧版本，更新保留预期旧版本', () {
      final update = LibraryCommand.fromJson(commandJson());
      expect(update.target.libraryId, 'lib-a');
      expect(update.payload['expectedVersionId'], 'v2');
      final create = commandJson();
      create['payload']['expectedVersionId'] = null;
      expect(
        LibraryCommand.fromJson(create).payload['expectedVersionId'],
        isNull,
      );
    });

    test('相同重试内容的嵌套字段顺序不影响指纹依据', () {
      final first = LibraryCommand.fromJson(commandJson());
      final reversed = commandJson();
      final version = reversed['payload']['version'] as Json;
      reversed['payload']['version'] = {
        for (final key in version.keys.toList().reversed) key: version[key],
      };
      reversed['target'] = {
        'workId': null,
        'libraryId': 'lib-a',
        'kind': 'library',
      };
      expect(LibraryCommand.fromJson(reversed).canonical, first.canonical);
      expect(
        LibraryCommand.fromJson(first.toJson()).canonical,
        first.canonical,
      );
    });

    test('请求目标、来源版本、内容和修订号都属于指纹依据', () {
      final original = LibraryCommand.fromJson(commandJson()).canonical;
      for (final edit in <void Function(Json)>[
        (j) => j['target']['libraryId'] = 'lib-b',
        (j) => j['payload']['expectedVersionId'] = 'v1',
        (j) => j['payload']['version']['body'] = '另一份正文',
        (j) => j['expectedRevision'] = 11,
        (j) => j['requestId'] = 'other-request',
        (j) =>
            j['payload']['version']['provenance']['sources'][0]['reference'] =
                'https://example.com/other',
      ]) {
        final json = commandJson();
        edit(json);
        expect(LibraryCommand.fromJson(json).canonical, isNot(original));
      }
    });

    test('接收后深层修改与界面切换不改变原请求', () {
      final json = commandJson();
      final command = LibraryCommand.fromJson(json);
      final original = command.canonical;
      json['target']['libraryId'] = 'lib-b';
      json['payload']['version']['body'] = '后来编辑的内容';
      json['payload']['version']['provenance']['sources'].clear();
      expect(command.canonical, original);
      expect(command.target.libraryId, 'lib-a');
      expect(
        () => command.payload['version']['body'] = '变化',
        throwsUnsupportedError,
      );
      expect(
        () => command.payload['version']['provenance']['sources'].clear(),
        throwsUnsupportedError,
      );
    });

    test('关联作品只是显式来源归属，必须与请求目标一致', () {
      final json = commandJson();
      json['target']['workId'] = 'work-a';
      json['payload']['version']['associatedWorkId'] = 'work-a';
      expect(LibraryCommand.fromJson(json).target.workId, 'work-a');
      json['payload']['version']['associatedWorkId'] = 'work-b';
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
    });

    test('调用方请求的作者正文与要求不被 trim', () {
      final json = commandJson(
        operation: 'proposeEdit',
        target: {'kind': 'work', 'workId': 'work-a'},
        payload: {
          'chapterId': 'chapter-1',
          'start': 0,
          'end': 2,
          'instruction': '  保留雨声\n  ',
        },
      );
      expect(
        LibraryCommand.fromJson(json).payload['instruction'],
        '  保留雨声\n  ',
      );
    });

    test('讨论请求绑定作品和讨论，轮次 requestId 与消息身份分别保留', () {
      final command = LibraryCommand.fromJson(
        commandJson(
          operation: 'sendDiscussionMessage',
          target: {
            'kind': 'discussion',
            'workId': 'work-a',
            'discussionId': 'discussion-1',
          },
          payload: {'messageId': 'author-next', 'body': '下一轮构思'},
        ),
      );
      expect(command.target.workId, 'work-a');
      expect(command.target.discussionId, 'discussion-1');
      expect(command.payload['messageId'], 'author-next');
      LibraryWorkspace.fromJson(
        libraryFixture(),
      ).validateTarget(command.target);
    });

    test('讨论转资料明确身份、版本与原消息；缺失来源时拒绝', () {
      final source = {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
        'messageId': 'assistant-1',
      };
      final version = versionJson('result-v1', kind: 'plan', workId: 'work-a');
      version['provenance']['sources'] = [source];
      final json = commandJson(
        operation: 'adoptDiscussionMessage',
        target: {'kind': 'library', 'libraryId': 'lib-a', 'workId': 'work-a'},
        payload: {
          'source': source,
          'documentId': 'result',
          'expectedVersionId': null,
          'version': version,
        },
      );
      expect(LibraryCommand.fromJson(json).payload['version']['kind'], 'plan');
      json['payload']['version']['provenance']['sources'] = [
        {'kind': 'author', 'reference': '作者输入'},
      ];
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
    });

    test('讨论转正文先成为同作品提案，不直接保存正文', () {
      final json = commandJson(
        operation: 'adoptDiscussionMessage',
        target: {'kind': 'work', 'workId': 'work-a'},
        payload: {
          'source': {
            'kind': 'discussion',
            'workId': 'work-a',
            'discussionId': 'discussion-1',
            'messageId': 'assistant-1',
          },
          'proposal': proposalJson(),
        },
      );
      json['payload']['proposal']['discussionSource'] =
          json['payload']['source'];
      expect(
        LibraryCommand.fromJson(json).payload['proposal']['proposal']['status'],
        'pending',
      );
      json['payload']['proposal']['discussionSource'] = null;
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
      json['payload']['proposal']['discussionSource'] = jsonCopy(
        json['payload']['source'],
      );
      json['payload']['proposal']['discussionSource']['messageId'] =
          'other-message';
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
      json['payload']['proposal']['discussionSource'] = jsonCopy(
        json['payload']['source'],
      );
      json['payload']['proposal']['proposal']['status'] = 'accepted';
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
      json['payload']['proposal']['proposal']['status'] = 'pending';
      json['payload']['source']['workId'] = 'work-b';
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
    });

    final operations = <String, (Json, Json)>{
      'createChapter': (
        {'kind': 'work', 'workId': 'work-a'},
        {'chapterId': 'manual-chapter', 'title': '第一章'},
      ),
      'createWork': ({'kind': 'catalog'}, {'id': 'work-c', 'title': '新作品'}),
      'createLibrary': ({'kind': 'catalog'}, {'id': 'lib-c', 'name': '新资料库'}),
      'renameWork': ({'kind': 'work', 'workId': 'work-a'}, {'title': '新名称'}),
      'renameLibrary': (
        {'kind': 'library', 'libraryId': 'lib-a', 'workId': null},
        {'name': '新名称'},
      ),
      'setKnowledgeLinks': (
        {'kind': 'work', 'workId': 'work-a'},
        {
          'links': [
            {
              'libraryId': 'lib-a',
              'versions': {'shared': 'v2'},
            },
          ],
        },
      ),
      'createDiscussion': (
        {'kind': 'work', 'workId': 'work-a'},
        {'id': 'discussion-next', 'title': '构思', 'chapterId': null},
      ),
      'proposeChapter': (
        {'kind': 'work', 'workId': 'work-a'},
        {'instruction': '继续写'},
      ),
      'saveChapter': (
        {'kind': 'work', 'workId': 'work-a'},
        {'chapterId': 'chapter-1', 'body': '作者正文'},
      ),
      'restoreVersion': (
        {'kind': 'work', 'workId': 'work-a'},
        {'chapterId': 'chapter-1', 'versionId': 'text-1'},
      ),
      'acceptProposal': (
        {'kind': 'work', 'workId': 'work-a'},
        {'proposalId': 'proposal-1'},
      ),
      'rejectProposal': (
        {'kind': 'work', 'workId': 'work-a'},
        {'proposalId': 'proposal-1'},
      ),
      'rebuildMemory': ({'kind': 'work', 'workId': 'work-a'}, {}),
      'confirmReview': (
        {'kind': 'work', 'workId': 'work-a'},
        {'chapterId': 'chapter-1'},
      ),
    };
    for (final entry in operations.entries) {
      test('${entry.key} 保留明确的目标与操作内容', () {
        final json = commandJson(
          operation: entry.key,
          target: entry.value.$1,
          payload: entry.value.$2,
        );
        expect(LibraryCommand.fromJson(json).toJson(), json);
      });
    }
  });

  group('无效请求拒绝', () {
    final invalid = <String, void Function(Json)>{
      '缺失目标': (j) => j.remove('target'),
      '空目标': (j) => j['target'] = null,
      '未知请求字段': (j) => j['activeWorkId'] = 'work-b',
      '混合目标身份': (j) => j['target']['discussionId'] = 'discussion-1',
      '知识库目标缺失显式可空作品': (j) => j['target'].remove('workId'),
      '未知目标': (j) => j['target']['kind'] = 'active',
      '空白目标': (j) => j['target']['libraryId'] = ' ',
      '未知操作': (j) => j['operation'] = 'executeImportedInstructions',
      '操作目标不匹配': (j) => j['target'] = {'kind': 'work', 'workId': 'work-a'},
      '旧请求协议': (j) => j['apiVersion'] = 1,
      '浮点请求协议': (j) => j['apiVersion'] = 2.0,
      '浮点修订号': (j) => j['expectedRevision'] = 10.0,
      '负修订号': (j) => j['expectedRevision'] = -1,
      '缺失旧资料版本': (j) => j['payload'].remove('expectedVersionId'),
      '数字资料版本': (j) => j['payload']['expectedVersionId'] = 2,
      '原地重写资料版本': (j) => j['payload']['version']['id'] = 'v2',
      '未知 payload 字段': (j) => j['payload']['applyToBody'] = true,
      '非法来源身份': (j) => j['payload']['version']['kind'] = 'acceptedFact',
    };
    for (final entry in invalid.entries) {
      test(entry.key, () {
        final json = commandJson();
        entry.value(json);
        expect(() => LibraryCommand.fromJson(json), throwsFormatException);
      });
    }

    test('非法或空选段被拒绝', () {
      for (final range in [(0, 0), (2, 1), (-1, 2)]) {
        expect(
          () => LibraryCommand.fromJson(
            commandJson(
              operation: 'proposeEdit',
              target: {'kind': 'work', 'workId': 'work-a'},
              payload: {
                'chapterId': 'chapter-1',
                'start': range.$1,
                'end': range.$2,
                'instruction': '改写',
              },
            ),
          ),
          throwsFormatException,
        );
      }
    });

    test('重复库关联和非整数选段被拒绝', () {
      expect(
        () => LibraryCommand.fromJson(
          commandJson(
            operation: 'setKnowledgeLinks',
            target: {'kind': 'work', 'workId': 'work-a'},
            payload: {
              'links': [
                {'libraryId': 'lib-a', 'versions': {}},
                {'libraryId': 'lib-a', 'versions': {}},
              ],
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => LibraryCommand.fromJson(
          commandJson(
            operation: 'proposeEdit',
            target: {'kind': 'work', 'workId': 'work-a'},
            payload: {
              'chapterId': 'chapter-1',
              'start': 0.0,
              'end': 2,
              'instruction': '改写',
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('JSON 来源不能夹带非有限数值或对象', () {
      final json = commandJson();
      json['payload']['version']['provenance']['writer']['id'] = double.nan;
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
      json['payload']['version']['provenance']['writer']['id'] = Object();
      expect(() => LibraryCommand.fromJson(json), throwsFormatException);
    });
  });
}
