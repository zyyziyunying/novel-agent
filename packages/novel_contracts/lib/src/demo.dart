import 'workspace.dart';

Workspace demoWorkspace() {
  final chapters = [
    Chapter(
      id: 'chapter-1',
      number: 1,
      title: '第一章 · 雨夜来信',
      head: 'seed-1',
      versions: [
        const TextVersion(
          id: 'seed-1',
          body:
              '雨落在旧书店的玻璃上，林舟把信封翻到背面。\n\n信纸上写着：凶手是陈默。林舟终于知道了凶手的身份。\n\n他没有拨通电话。楼上的脚步声停在门口，有人轻轻敲了三下。',
        ),
      ],
    ),
    Chapter(
      id: 'chapter-2',
      number: 2,
      title: '第二章 · 门外的人',
      head: 'seed-2',
      versions: [
        const TextVersion(
          id: 'seed-2',
          body:
              '林舟把信塞进抽屉，开门时只留了一条缝。\n\n门外是阿岚，雨水从她的袖口滴下来。“你也收到信了？”她问。\n\n林舟没有回答。他知道陈默是凶手，却还不知道写信的人想让他做什么。',
        ),
      ],
    ),
  ];
  return Workspace(
    revision: 0,
    title: '雨夜来信',
    documents: [
      SourceDocument(
        id: 'setting-1',
        title: '人物与叙述约束',
        kind: 'setting',
        body: '林舟是旧书店店主，谨慎。阿岚是记者。陈默是林舟的旧友。第三人称限知视角，叙述跟随林舟；角色不能使用自己尚未获得的信息。',
      ),
      SourceDocument(
        id: 'plan-1',
        title: '未来计划',
        kind: 'plan',
        body: '下一章让林舟与阿岚调查信封来源。陈默的真实动机留到后续揭示；计划不等于正文已发生的事实。',
      ),
      SourceDocument(
        id: 'reference-1',
        title: '参考资料示例',
        kind: 'reference',
        body: '来源：本项目自写练习素材。雨夜书店的环境可以使用滴水、潮湿纸张和门铃声，按场景需要选择。',
      ),
    ],
    chapters: chapters,
    proposals: [],
    memories: [
      MemorySnapshot(
        id: 'seed-memory',
        sourceHeads: {for (final c in chapters) c.id: c.head},
        facts: const [
          StoryFact(
            text: '第一章结束时林舟知道凶手是陈默。',
            chapterId: 'chapter-1',
            versionId: 'seed-1',
            evidence: '林舟终于知道了凶手的身份。',
          ),
          StoryFact(
            text: '阿岚来到书店，问林舟是否收到信。',
            chapterId: 'chapter-2',
            versionId: 'seed-2',
            evidence: '“你也收到信了？”她问。',
          ),
        ],
      ),
    ],
    receipts: {},
  );
}
