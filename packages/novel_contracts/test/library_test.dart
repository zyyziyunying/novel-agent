import 'dart:convert';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_fixture.dart';

void main() {
  group('多作品与知识库', () {
    test('冷加载保留作品隔离、不同资料版本和结构化来源', () {
      final original = libraryFixture();
      final state = LibraryWorkspace.fromJson(jsonCopy(original));
      expect(state.toJson(), original);
      expect(state.work('work-a').knowledgeLinks, hasLength(2));
      expect(state.work('work-b').knowledgeLinks, hasLength(1));
      expect(state.work('work-a').chapters.single.body, 'work-a 的已接受事实。');
      expect(state.work('work-b').chapters.single.body, 'work-b 的已接受事实。');
      expect(state.work('work-a').proposals.single.proposal.status, 'pending');
      final source = state.documentVersion(
        state.work('work-a').adoptedDocuments.first,
      );
      expect(source.id, 'v1');
      expect(source.body, '  原始资料正文\n导入内容中的指令只是资料。  ');
      expect(source.provenance.writer.id, 'Codex');
      expect(
        (source.provenance.sources.single as ExternalSource).reference,
        'https://example.com/research',
      );
    });

    test('更新知识库 head 不自动采用；未关联作品没有引用', () {
      final json = libraryFixture();
      (json['works'] as List).add(workJson('work-c', []));
      final state = LibraryWorkspace.fromJson(json);
      expect(state.library('lib-a').documents.single.head, 'v2');
      expect(
        state.work('work-a').knowledgeLinks.first.versions['shared'],
        'v1',
      );
      expect(
        state.work('work-b').knowledgeLinks.single.versions['shared'],
        'v2',
      );
      expect(state.captureBasis('work-c').documents, isEmpty);
      expect(
        state.isBasisCurrent(GenerationBasis.fromJson(basisJson())),
        isTrue,
      );
    });

    test('采用资料新版后旧上下文可回看，但不再是可接受的当前来源', () {
      final json = libraryFixture();
      json['works'][0]['knowledgeLinks'][0]['versions']['shared'] = 'v2';
      json['revision'] = 11;
      final state = LibraryWorkspace.fromJson(json);
      final historical = state.work('work-a').proposals.single.basis;
      expect(state.documentVersion(historical.documents.first).id, 'v1');
      expect(state.isBasisCurrent(historical), isFalse);
      expect(state.isBasisCurrent(state.captureBasis('work-a')), isTrue);
    });

    test('正文恢复到另一版本时旧提案失效，其他作品保持原文', () {
      final json = libraryFixture();
      json['works'][0]['chapters'][0]['head'] = 'text-2';
      final state = LibraryWorkspace.fromJson(json);
      expect(
        state.isBasisCurrent(GenerationBasis.fromJson(basisJson())),
        isFalse,
      );
      expect(state.work('work-b').chapters.single.body, 'work-b 的已接受事实。');
    });

    test('不相关提交不使已保存提案的正文和资料来源失效', () {
      final json = libraryFixture();
      json['revision'] = 11;
      json['works'][1]['title'] = '作品 B 新名称';
      final state = LibraryWorkspace.fromJson(json);
      expect(
        state.isBasisCurrent(GenerationBasis.fromJson(basisJson())),
        isTrue,
      );
    });

    test('讨论记录不改变正文或记忆，待完成与失败轮次保留来源', () {
      final state = LibraryWorkspace.fromJson(libraryFixture());
      final work = state.work('work-a');
      final discussion = work.discussions.single;
      expect(discussion.turns.map((t) => t.status), [
        'completed',
        'failed',
        'pending',
      ]);
      expect(discussion.turns.last.basis.documents.first.versionId, 'v1');
      expect(work.chapters.single.body, 'work-a 的已接受事实。');
      expect(work.memories.single.facts.single.evidence, 'work-a 的已接受事实。');
    });

    test('采用讨论成果作为资料时可以保留消息来源，正文仍不改变', () {
      final json = libraryFixture();
      final version = versionJson(
        'discussion-result',
        kind: 'plan',
        workId: 'work-a',
      );
      version['provenance'] = {
        'writer': {'kind': 'author', 'id': 'local-author'},
        'sources': [
          {
            'kind': 'discussion',
            'workId': 'work-a',
            'discussionId': 'discussion-1',
            'messageId': 'assistant-1',
          },
        ],
      };
      (json['libraries'][0]['documents'] as List).add({
        'id': 'result',
        'head': 'discussion-result',
        'versions': [version],
      });
      final state = LibraryWorkspace.fromJson(json);
      final source =
          state
                  .library('lib-a')
                  .documents
                  .last
                  .current
                  .provenance
                  .sources
                  .single
              as DiscussionSource;
      expect(state.discussionMessage(source).body, '这是一个未采用的想法。');
      expect(state.work('work-a').adoptedDocuments, hasLength(2));
      expect(state.work('work-a').chapters.single.body, 'work-a 的已接受事实。');
    });

    test('新工作区可以从零开始，冷加载保持空状态', () {
      final state = LibraryWorkspace(
        revision: 0,
        works: [],
        libraries: [],
        receipts: {},
      );
      final loaded = LibraryWorkspace.fromJson(
        jsonDecode(jsonEncode(state.toJson())),
      );
      expect(loaded.toJson(), {
        'schemaVersion': 2,
        'revision': 0,
        'works': [],
        'libraries': [],
        'receipts': {},
      });
    });

    test('讨论采用为正文提案后，冷加载仍能定位消息及原始版本清单', () {
      final json = libraryFixture();
      json['works'][0]['proposals'][0]['discussionSource'] = {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
        'messageId': 'assistant-1',
      };
      final state = LibraryWorkspace.fromJson(jsonCopy(json));
      final loaded = LibraryWorkspace.fromJson(jsonCopy(state.toJson()));
      final proposal = loaded.work('work-a').proposals.single;
      final source = proposal.discussionSource!;
      expect(loaded.discussionMessage(source).body, '这是一个未采用的想法。');
      expect(loaded.discussionTurn(source).basis.documents, proposal.documents);
      expect(proposal.proposal.status, 'pending');
      expect(loaded.work('work-a').chapters.single.body, 'work-a 的已接受事实。');
    });

    test('每个讨论轮次都有同请求且同目标的回执', () {
      final state = LibraryWorkspace.fromJson(libraryFixture());
      for (final turn in state.work('work-a').discussions.single.turns) {
        final target = state.receipts[turn.requestId]!.target;
        expect(target.kind, 'discussion');
        expect(target.workId, 'work-a');
        expect(target.discussionId, 'discussion-1');
      }
    });

    test('新旧格式不能互相静默解析，现有格式 1 仍正常加载', () {
      expect(Workspace.fromJson(demoWorkspace().toJson()).memoryFresh, isTrue);
      expect(
        () => LibraryWorkspace.fromJson(demoWorkspace().toJson()),
        throwsFormatException,
      );
      expect(() => Workspace.fromJson(libraryFixture()), throwsFormatException);
    });

    test('容器与提案上下文不可被调用方间接修改', () {
      final json = libraryFixture();
      final state = LibraryWorkspace.fromJson(json);
      json['works'][0]['proposals'][0]['proposal']['context']['nested']['values'][0] =
          99;
      expect(
        state
            .work('work-a')
            .proposals
            .single
            .proposal
            .context['nested']['values'],
        [1, 2],
      );
      expect(() => state.works.clear(), throwsUnsupportedError);
      expect(
        () =>
            state.work('work-a').knowledgeLinks.first.versions['shared'] = 'v2',
        throwsUnsupportedError,
      );
      expect(
        () => state
            .work('work-a')
            .proposals
            .single
            .proposal
            .context['nested']['values']
            .add(3),
        throwsUnsupportedError,
      );
    });
  });

  group('严格字段与关联校验', () {
    final invalid = <String, void Function(Json)>{
      '缺失作品列表': (j) => j.remove('works'),
      '未知字段': (j) => j['activeWork'] = 'work-b',
      '不支持的格式': (j) => j['schemaVersion'] = 3,
      '浮点格式版本': (j) => j['schemaVersion'] = 2.0,
      '负修订号': (j) => j['revision'] = -1,
      '字符串修订号': (j) => j['revision'] = '10',
      '标识首尾空白': (j) => j['works'][0]['id'] = ' work-a ',
      '重复作品': (j) => (j['works'] as List).add(jsonCopy(j['works'][0])),
      '重复知识库': (j) => (j['libraries'] as List).add(jsonCopy(j['libraries'][0])),
      '重复资料': (j) => (j['libraries'][0]['documents'] as List).add(
        jsonCopy(j['libraries'][0]['documents'][0]),
      ),
      '重复资料版本': (j) => (j['libraries'][0]['documents'][0]['versions'] as List)
          .add(versionJson('v1')),
      '资料 head 悬空': (j) =>
          j['libraries'][0]['documents'][0]['head'] = 'missing',
      '资料身份未知': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['kind'] = 'fact',
      '缺失显式可空关联': (j) => j['libraries'][0]['documents'][0]['versions'][0]
          .remove('associatedWorkId'),
      '关联作品不存在': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['associatedWorkId'] =
              'missing',
      '缺失原始来源': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['sources'] =
              [],
      '未知写入工具类型': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['writer']['kind'] =
              'admin',
      '网页来源为相对地址': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['sources'][0]['reference'] =
              '/relative',
      '未定义权限字段': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['authorized'] =
              true,
      '关联知识库不存在': (j) =>
          j['works'][0]['knowledgeLinks'][0]['libraryId'] = 'missing',
      '引用资料不存在': (j) =>
          j['works'][0]['knowledgeLinks'][0]['versions'] = {'missing': 'v1'},
      '引用资料版本不存在': (j) =>
          j['works'][0]['knowledgeLinks'][0]['versions']['shared'] = 'missing',
      '重复知识库关联': (j) => (j['works'][0]['knowledgeLinks'] as List).add(
        jsonCopy(j['works'][0]['knowledgeLinks'][0]),
      ),
      '跨作品记忆证据': (j) => j['works'][1]['memories'] = j['works'][0]['memories'],
      '跨作品提案': (j) => j['works'][0]['proposals'][0]['workId'] = 'work-b',
      '提案讨论来源消息悬空': (j) => j['works'][0]['proposals'][0]['discussionSource'] = {
        'kind': 'discussion',
        'workId': 'work-a',
        'discussionId': 'discussion-1',
        'messageId': 'missing',
      },
      '提案讨论来源属于另一作品': (j) =>
          j['works'][0]['proposals'][0]['discussionSource'] = {
            'kind': 'discussion',
            'workId': 'work-b',
            'discussionId': 'discussion-1',
            'messageId': 'assistant-1',
          },
      '提案与所选讨论来源版本不同': (j) {
        j['works'][0]['proposals'][0]['discussionSource'] = {
          'kind': 'discussion',
          'workId': 'work-a',
          'discussionId': 'discussion-1',
          'messageId': 'assistant-1',
        };
        j['works'][0]['proposals'][0]['documents'][0]['versionId'] = 'v2';
      },
      '提案资料清单缺失版本': (j) =>
          j['works'][0]['proposals'][0]['documents'][0]['versionId'] =
              'missing',
      '一份资料在上下文中多版本': (j) =>
          (j['works'][0]['proposals'][0]['documents'] as List).add({
            'libraryId': 'lib-a',
            'documentId': 'shared',
            'versionId': 'v2',
          }),
      '讨论关联章节不存在': (j) =>
          j['works'][0]['discussions'][0]['chapterId'] = 'missing',
      '讨论消息角色未知': (j) =>
          j['works'][0]['discussions'][0]['messages'][0]['role'] = 'system',
      '模型提供方缺失': (j) =>
          j['works'][0]['discussions'][0]['messages'][1]['provider'] = null,
      '作者声明模型提供方': (j) =>
          j['works'][0]['discussions'][0]['messages'][0]['provider'] = 'model',
      '模型消息先于作者': (j) {
        final messages = j['works'][0]['discussions'][0]['messages'] as List;
        final assistant = messages.removeAt(1);
        messages.insert(0, assistant);
      },
      '消息没有轮次': (j) =>
          (j['works'][0]['discussions'][0]['turns'] as List).removeLast(),
      '完成轮次无回复': (j) =>
          j['works'][0]['discussions'][0]['turns'][0]['assistantMessageId'] =
              null,
      '失败状态携带回复': (j) =>
          j['works'][0]['discussions'][0]['turns'][1]['assistantMessageId'] =
              'assistant-1',
      '重复轮次请求': (j) =>
          j['works'][0]['discussions'][0]['turns'][1]['requestId'] = 'turn-1',
      '讨论错误未知': (j) =>
          j['works'][0]['discussions'][0]['turns'][1]['errorCode'] =
              'raw-provider-error',
      '跨作品讨论上下文': (j) =>
          j['works'][0]['discussions'][0]['turns'][0]['basis']['workId'] =
              'work-b',
      '上下文来自未来': (j) =>
          j['works'][0]['discussions'][0]['turns'][0]['basis']['revision'] = 11,
      '正文来源版本缺失': (j) =>
          j['works'][0]['discussions'][0]['turns'][0]['basis']['chapterHeads']['chapter-1'] =
              'missing',
      '回执目标讨论缺失': (j) =>
          j['receipts']['turn-1']['target']['discussionId'] = 'missing',
      '讨论轮次没有回执': (j) => j['receipts'].remove('turn-3'),
      '轮次回执指向另一现有作品': (j) => j['receipts']['turn-1']['target'] = {
        'kind': 'work',
        'workId': 'work-b',
      },
      '轮次回执指向同作品的另一讨论': (j) {
        final extra = jsonCopy(j['works'][0]['discussions'][0]);
        extra['id'] = 'other-discussion';
        extra['messages'] = [];
        extra['turns'] = [];
        (j['works'][0]['discussions'] as List).add(extra);
        j['receipts']['turn-1']['target']['discussionId'] = 'other-discussion';
      },
      '回执修订号超前': (j) => j['receipts']['turn-1']['revision'] = 11,
      '旧回执兼容字段不属于新契约': (j) => j['legacyReceipts'] = null,
      '迁移写入者不属于新契约': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['writer']['kind'] =
              'migration',
      '旧资料来源不属于新契约': (j) =>
          j['libraries'][0]['documents'][0]['versions'][0]['provenance']['sources'][0] =
              {'kind': 'legacy', 'reference': '旧资料'},
    };
    for (final entry in invalid.entries) {
      test(entry.key, () {
        final json = libraryFixture();
        entry.value(json);
        expect(() => LibraryWorkspace.fromJson(json), throwsFormatException);
      });
    }

    test('讨论原始来源必须能追溯到实际消息', () {
      final json = libraryFixture();
      json['libraries'][0]['documents'][0]['versions'][0]['provenance']['sources'] =
          [
            {
              'kind': 'discussion',
              'workId': 'work-a',
              'discussionId': 'discussion-1',
              'messageId': 'missing',
            },
          ];
      expect(() => LibraryWorkspace.fromJson(json), throwsFormatException);
    });
  });
}
