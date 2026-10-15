import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_fixture.dart';

void main() {
  test('旧格式 2 快照及版本无损往返，未填写简介保持全文读取', () {
    final original = libraryFixture();
    final workspace = LibraryWorkspace.fromJson(original);
    expect(workspace.toJson(), original);
    final version = workspace.libraries.first.documents.first.current;
    expect(version.description, isEmpty);
    expect(version.tags, isEmpty);
    expect(version.alwaysRead, isFalse);
    expect(version.requiresFullText, isTrue);
  });

  test('简介、标签和必读设置绑定资料版本，标签不可变，正文原样保存', () {
    final json = versionJson('v3')
      ..addAll({
        'description': '涉及影子行动时读取。',
        'tags': ['影子', '规则'],
        'alwaysRead': true,
      });
    final version = KnowledgeVersion.fromJson(json);
    expect(version.toJson(), json);
    expect(version.requiresFullText, isTrue);
    expect(() => version.tags.add('新标签'), throwsUnsupportedError);
    expect(
      KnowledgeVersion.fromJson({
        ...json,
        'alwaysRead': false,
      }).requiresFullText,
      isFalse,
    );
  });

  test('新增字段拒绝显式 null、错误类型、重复标签、超长和未知字段', () {
    for (final patch in <Json>[
      {'description': null},
      {'description': 12},
      {'description': 'x' * 501},
      {'tags': null},
      {'tags': '影子'},
      {
        'tags': [12],
      },
      {
        'tags': [''],
      },
      {
        'tags': [' 影子'],
      },
      {
        'tags': ['影子', '影子'],
      },
      {
        'tags': ['x' * 41],
      },
      {'tags': List.generate(21, (i) => 'tag$i')},
      {
        'tags': ['甲,乙'],
      },
      {
        'tags': ['甲，乙'],
      },
      {
        'tags': ['甲\n乙'],
      },
      {
        'tags': ['甲\r乙'],
      },
      {'alwaysRead': null},
      {'alwaysRead': 'true'},
      {'autoExecute': true},
    ]) {
      expect(
        () => KnowledgeVersion.fromJson({...versionJson('v3'), ...patch}),
        throwsFormatException,
        reason: '$patch',
      );
    }
  });

  test('目录只包含指定版本的简介与标签，不包含正文或来源内容', () {
    final json = libraryFixture();
    json['libraries'][0]['documents'][0]['versions'][0]['description'] = '旧版简介';
    json['libraries'][0]['documents'][0]['versions'][1]['description'] = '新版简介';
    final workspace = LibraryWorkspace.fromJson(json);
    final catalog = knowledgeCatalog(
      workspace,
      workspace.captureBasis('work-a'),
    );
    expect(catalog.first['description'], '旧版简介');
    expect(catalog.first.containsKey('body'), isFalse);
    expect(catalog.first.containsKey('provenance'), isFalse);
  });

  test('讨论读取清单区分未记录与空清单，拒绝目录外版本和遗漏必读', () {
    final original = discussionJson()['turns'][0] as Json;
    expect(DiscussionTurn.fromJson(original).readDocuments, isNull);
    expect(
      DiscussionTurn.fromJson({...original, 'readDocuments': []}).readDocuments,
      isEmpty,
    );
    for (final refs in [
      null,
      [
        {'libraryId': 'lib-a', 'documentId': 'shared', 'versionId': 'v2'},
      ],
      [basisJson()['documents'][0], basisJson()['documents'][0]],
    ]) {
      expect(
        () => DiscussionTurn.fromJson({...original, 'readDocuments': refs}),
        throwsFormatException,
      );
    }
    final snapshot = libraryFixture();
    snapshot['works'][0]['discussions'][0]['turns'][0]['readDocuments'] = [];
    expect(() => LibraryWorkspace.fromJson(snapshot), throwsFormatException);
  });
}
