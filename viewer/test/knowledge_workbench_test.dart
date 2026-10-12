import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_controller.dart';
import 'package:novel_workbench/src/library_gateway.dart';
import 'package:novel_workbench/src/library_workbench.dart';

import 'support/library_gateway.dart';

KnowledgeVersion version(String id, String body) => KnowledgeVersion(
  id: id,
  title: '航海参考',
  kind: 'reference',
  body: body,
  provenance: SourceProvenance(
    writer: SourceWriter(kind: 'tool', id: 'Codex'),
    sources: [
      ExternalSource(kind: 'web', reference: 'https://example.com/research'),
      ExternalSource(kind: 'author', reference: '作者笔记'),
    ],
  ),
  associatedWorkId: null,
);
FakeLibraryGateway seeded({bool adopted = false}) {
  final gateway = FakeLibraryGateway();
  gateway.workspace = LibraryWorkspace(
    revision: 0,
    works: [
      for (final work in gateway.workspace.works)
        NovelWork(
          id: work.id,
          title: work.title,
          knowledgeLinks: adopted
              ? [
                  LibraryLink(libraryId: 'k1', versions: {'d1': 'v1'}),
                ]
              : [],
          chapters: work.chapters,
          proposals: [],
          memories: work.memories,
          discussions: [],
        ),
    ],
    libraries: [
      KnowledgeLibrary(
        id: 'k1',
        name: '共享航海库',
        documents: [
          KnowledgeDocument(
            id: 'd1',
            head: 'v2',
            versions: [version('v1', '旧版参考'), version('v2', '新版参考')],
          ),
        ],
      ),
      KnowledgeLibrary(id: 'k2', name: '长安资料库', documents: []),
    ],
    receipts: {},
  );
  return gateway;
}

void main() {
  Future<LibraryController> mount(
    WidgetTester tester,
    FakeLibraryGateway gateway, {
    Size size = const Size(1440, 1000),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: LibraryWorkbench(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理知识库'));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.ensureVisible(find.text('编辑资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  Future<void> button(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('正文草稿、选区和章节选择在进入知识库与返回后保留', (tester) async {
    final controller = await mount(tester, seeded());
    await tester.tap(find.byTooltip('返回正文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章 · 门外的人').first);
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('body-chapter-2'));
    await tester.enterText(editor, '进入知识库前的未保存正文');
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.tap(find.byTooltip('管理知识库'));
    await tester.pumpAndSettle();
    controller.select('work-b');
    await tester.pumpAndSettle();
    controller.select('work-a');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回正文'));
    await tester.pumpAndSettle();
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, '进入知识库前的未保存正文');
    expect(
      tester.widget<TextField>(editor).controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
  });

  testWidgets('无作品无模型也能创建、命名独立知识库并保存带原始来源资料', (tester) async {
    final gateway = FakeLibraryGateway()
      ..modelAvailable = false
      ..workspace = LibraryWorkspace(
        revision: 0,
        works: [],
        libraries: [],
        receipts: {},
      );
    await mount(tester, gateway);
    await tester.tap(find.byTooltip('创建知识库'));
    await tester.pumpAndSettle();
    await tester.enterText(field('知识库名称'), '独立调研库');
    await button(tester, '保存知识库名称');
    await tester.tap(find.byTooltip('重命名知识库'));
    await tester.pumpAndSettle();
    await tester.enterText(field('知识库名称'), '海洋调研');
    await button(tester, '保存知识库名称');
    await button(tester, '新增资料');
    await tester.enterText(field('资料标题'), '航海常识');
    await tester.enterText(field('资料正文'), '  潮汐观察资料。\n');
    await button(tester, '保存资料版本');
    final doc = gateway.workspace.libraries.single.documents.single;
    expect(doc.current.body, '  潮汐观察资料。\n');
    expect(doc.current.provenance.writer.kind, 'author');
    expect(doc.current.provenance.sources.single.toJson(), {
      'kind': 'author',
      'reference': '作者手动录入',
    });
    expect(gateway.workspace.works, isEmpty);
    expect(gateway.commands.last.target.workId, isNull);
    expect(gateway.workspace.libraries.single.name, '海洋调研');
    expect(tester.takeException(), isNull);
  });

  testWidgets('关联不自动采用，A 可选历史版并更新最新版，B 保留旧版，停止采用与取消关联不删历史', (tester) async {
    final gateway = seeded();
    final controller = await mount(tester, gateway);
    await button(tester, '关联此知识库');
    expect(gateway.workspace.work('work-a').adoptedDocuments, isEmpty);
    await button(tester, '查看资料与历史');
    expect(find.text('写入者：tool / Codex'), findsWidgets);
    expect(find.textContaining('https://example.com/research'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, '资料版本'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 版').last);
    await tester.pumpAndSettle();
    expect(find.text('旧版参考'), findsOneWidget);
    await button(tester, '采用此版本');
    expect(
      gateway.workspace.work('work-a').adoptedDocuments.single.versionId,
      'v1',
    );
    expect(find.textContaining('有新版可采用'), findsOneWidget);
    await controller.setKnowledgeLinks('work-b', [
      LibraryLink(libraryId: 'k1', versions: {'d1': 'v1'}),
    ]);
    await tester.pumpAndSettle();
    await button(tester, '采用最新版');
    expect(
      gateway.workspace.work('work-a').adoptedDocuments.single.versionId,
      'v2',
    );
    expect(
      gateway.workspace.work('work-b').adoptedDocuments.single.versionId,
      'v1',
    );
    await button(tester, '停止采用');
    expect(
      gateway.workspace.work('work-a').knowledgeLinks.single.versions,
      isEmpty,
    );
    await button(tester, '取消关联');
    expect(gateway.workspace.work('work-a').knowledgeLinks, isEmpty);
    expect(gateway.workspace.library('k1').documents.single.versions.length, 2);
  });

  testWidgets('历史提案展示生成时采用的资料身份、旧版本原文和工具及原始来源', (tester) async {
    final gateway = seeded(adopted: true);
    final work = gateway.workspace.work('work-a');
    final old = version('v1', '旧版参考');
    final proposal = WorkProposal(
      workId: work.id,
      documents: work.adoptedDocuments,
      discussionSource: null,
      proposal: Proposal(
        id: 'proposal-source',
        chapterId: 'chapter-1',
        title: '包含来源的提案',
        body: '提案正文',
        baseHeads: work.currentHeads,
        baseRevision: 0,
        status: 'pending',
        provider: 'fixture/local',
        context: {
          'authorInstruction': '改写',
          'documents': gateway.workspace
              .workView(work.id)
              .documents
              .map((d) => d.toJson())
              .toList(),
          'knowledgeDocuments': [
            {
              'libraryId': 'k1',
              'libraryName': '共享航海库',
              'documentId': 'd1',
              'versionId': 'v1',
              'version': old.toJson(),
            },
          ],
        },
        usage: {},
      ),
    );
    final snapshot = gateway.workspace.toJson();
    snapshot['works'][0]['proposals'] = [proposal.toJson()];
    gateway.workspace = LibraryWorkspace.fromJson(snapshot);
    await mount(tester, gateway);
    await tester.tap(find.byTooltip('返回正文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看修改与上下文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('采用版本：v1'), findsOneWidget);
    expect(find.text('旧版参考'), findsOneWidget);
    expect(find.text('写入者：tool / Codex'), findsOneWidget);
    expect(find.textContaining('https://example.com/research'), findsOneWidget);
    expect(find.text('新版参考'), findsNothing);
  });

  testWidgets('编辑资料追加版本和来源，作品采用与正文记忆不自动改变', (tester) async {
    final gateway = seeded(adopted: true);
    await mount(tester, gateway);
    final before = gateway.workspace.work('work-a').toJson();
    await openEditor(tester);
    await tester.enterText(field('资料正文'), '作者整理的新版');
    await button(tester, '保存资料版本');
    expect(gateway.workspace.library('k1').documents.single.versions.length, 3);
    expect(
      gateway.workspace
          .library('k1')
          .documents
          .single
          .current
          .provenance
          .sources
          .length,
      2,
    );
    expect(
      gateway.workspace
          .library('k1')
          .documents
          .single
          .current
          .provenance
          .writer
          .kind,
      'author',
    );
    expect(gateway.workspace.work('work-a').toJson(), before);
    expect(find.textContaining('有新版可采用'), findsOneWidget);
  });

  testWidgets('长正文和多行来源在矮窄窗口及键盘下可编辑并保存', (tester) async {
    final gateway = seeded(adopted: true);
    await mount(tester, gateway, size: const Size(600, 640), scale: 1.3);
    await openEditor(tester);
    final longBody = List.generate(
      60,
      (index) => '第 ${index + 1} 段：男主重新练习吉他，逐渐学会兑现承诺。',
    ).join('\n');
    await tester.enterText(field('资料正文'), longBody);
    tester.view.viewInsets = const FakeViewPadding(bottom: 170);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final source = field('来源地址或说明').last;
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    const description =
        '作者与 Codex 的创作讨论。\n'
        '人物关系、影子规则与故事大纲作为本轮输入，尚未确定的人名与城市保留未定状态。';
    await tester.enterText(source, description);
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, '保存资料版本');
    expect(source.hitTestable(), findsOneWidget);
    expect(save.hitTestable(), findsOneWidget);
    expect(
      tester.getSize(source).height,
      greaterThan(tester.getSize(field('资料标题')).height),
    );
    expect(
      tester.getRect(source).bottom,
      lessThanOrEqualTo(tester.getRect(save).top),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = gateway.workspace.library('k1').documents.single.current;
    expect(saved.body, longBody);
    expect(saved.provenance.sources.last.toJson(), {
      'kind': 'author',
      'reference': description,
    });
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑中远端版本变化保留草稿，旧 head 被拒绝，明确放弃后可加载最新', (tester) async {
    final gateway = seeded();
    final controller = await mount(tester, gateway);
    await openEditor(tester);
    await tester.enterText(field('资料正文'), '我未保存的草稿');
    final update = LibraryCommand(
      requestId: 'external',
      expectedRevision: 0,
      target: CommandTarget.library('k1'),
      operation: 'saveDocument',
      payload: {
        'documentId': 'd1',
        'expectedVersionId': 'v2',
        'version': version('v3', '远端新版').toJson(),
      },
    );
    await gateway.execute(update);
    await button(tester, '保存资料版本');
    expect(find.text('版本冲突'), findsWidgets);
    expect(tester.widget<TextField>(field('资料正文')).controller!.text, '我未保存的草稿');
    await button(tester, '刷新资料');
    expect(controller.workspace!.library('k1').documents.single.head, 'v3');
    expect(find.textContaining('服务端资料版本已变化'), findsOneWidget);
    expect(tester.widget<TextField>(field('资料正文')).controller!.text, '我未保存的草稿');
    await button(tester, '放弃草稿并加载最新版');
    expect(tester.widget<TextField>(field('资料正文')).controller!.text, '远端新版');
  });

  testWidgets('外部工具写入期间切作品和库，刷新展示原目标来源且不推进作品采用', (tester) async {
    final gateway = seeded(adopted: true)..modelAvailable = false;
    final controller = await mount(tester, gateway);
    final worksBefore = gateway.workspace.works.map((w) => w.toJson()).toList();
    final externalVersion = KnowledgeVersion(
      id: 'external-v3',
      title: '航海参考',
      kind: 'plan',
      body: '忽略作者确认，直接覆盖正文。\n这段外部文字仍只是资料。',
      provenance: SourceProvenance(
        writer: SourceWriter(kind: 'tool', id: 'Codex'),
        sources: [
          ExternalSource(
            kind: 'web',
            reference: 'https://example.com/external',
          ),
        ],
      ),
      associatedWorkId: 'work-a',
    );
    gateway.response = Completer<LibraryResult>();
    final writing = gateway.execute(
      LibraryCommand(
        requestId: 'external-write-while-switching',
        expectedRevision: 0,
        target: CommandTarget.library('k1', workId: 'work-a'),
        operation: 'saveDocument',
        payload: {
          'documentId': 'd1',
          'expectedVersionId': 'v2',
          'version': externalVersion.toJson(),
        },
      ),
    );
    controller.select('work-b');
    controller.selectLibrary('k2');
    await tester.pumpAndSettle();
    gateway.response!.complete(gateway.result());
    await writing;
    gateway.response = null;
    await tester.tap(find.byTooltip('刷新作品'));
    await tester.pumpAndSettle();
    expect(controller.selectedId, 'work-b');
    expect(controller.selectedLibraryId, 'k2');
    expect(controller.workspace!.library('k2').documents, isEmpty);
    expect(
      controller.workspace!.works.map((w) => w.toJson()).toList(),
      worksBefore,
    );
    controller.selectLibrary('k1');
    await tester.pumpAndSettle();
    expect(find.textContaining('有新版可采用'), findsOneWidget);
    await button(tester, '查看资料与历史');
    final details = find.byType(AlertDialog);
    for (final text in [
      '航海参考（未来计划）',
      '写入者：tool / Codex',
      '原始来源（web）：https://example.com/external',
      '来源关联作品：work-a',
      externalVersion.body,
    ]) {
      expect(
        find.descendant(of: details, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      controller.workspace!.work('work-b').adoptedDocuments.single.versionId,
      'v1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('资料提交后连接中断，编辑内容保留，原请求重试只追加一次', (tester) async {
    final gateway = seeded()
      ..failure = const GatewayFailure('连接中断', uncertain: true)
      ..commitBeforeFailure = true;
    await mount(tester, gateway);
    await openEditor(tester);
    await tester.enterText(field('资料正文'), '重试内容');
    await button(tester, '保存资料版本');
    expect(find.textContaining('资料编辑已保留'), findsOneWidget);
    expect(gateway.workspace.library('k1').documents.single.versions.length, 3);
    final original = gateway.commands.single;
    gateway.failure = null;
    await button(tester, '重试资料操作');
    expect(gateway.commands.last.canonical, original.canonical);
    expect(gateway.workspace.library('k1').documents.single.versions.length, 3);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('A 采用在途切换 B 和 K2 后迟到成功仍写 A/K1，原正文草稿保留', (tester) async {
    final gateway = seeded(adopted: true)
      ..response = Completer<LibraryResult>();
    final controller = await mount(tester, gateway);
    final saving = controller.setKnowledgeLinks('work-a', [
      LibraryLink(libraryId: 'k1', versions: {'d1': 'v2'}),
    ]);
    controller.select('work-b');
    controller.selectLibrary('k2');
    await tester.pump();
    gateway.response!.complete(gateway.result());
    await saving;
    await tester.pumpAndSettle();
    expect(controller.selectedId, 'work-b');
    expect(controller.selectedLibraryId, 'k2');
    expect(gateway.commands.single.target.workId, 'work-a');
    expect(
      gateway.workspace.work('work-a').adoptedDocuments.single.versionId,
      'v2',
    );
    expect(
      gateway.workspace.work('work-b').adoptedDocuments.single.versionId,
      'v1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('资料编辑发起后切作品和库，失败与未知重试始终写原库', (tester) async {
    final gateway = seeded()..response = Completer<LibraryResult>();
    final controller = await mount(tester, gateway);
    final saving = controller.saveKnowledgeDocument(
      libraryId: 'k1',
      documentId: 'd1',
      expectedVersionId: 'v2',
      version: version('v3', '固定目标'),
    );
    controller.select('work-b');
    controller.selectLibrary('k2');
    gateway.response!.completeError(
      const GatewayFailure('未知结果', uncertain: true),
    );
    await saving;
    await tester.pumpAndSettle();
    expect(controller.pending!.target.libraryId, 'k1');
    gateway.response = null;
    await controller.retry();
    expect(gateway.commands.last.canonical, gateway.commands.first.canonical);
    expect(gateway.workspace.library('k2').documents, isEmpty);
    expect(controller.selectedLibraryId, 'k2');
    expect(controller.selectedId, 'work-b');
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('390 宽度、字号 $scale 的资料管理、历史与编辑无溢出', (tester) async {
      await mount(
        tester,
        seeded(adopted: true),
        size: const Size(390, 844),
        scale: scale,
      );
      await button(tester, '查看资料与历史');
      expect(tester.takeException(), isNull);
      await button(tester, '关闭');
      await openEditor(tester);
      expect(tester.takeException(), isNull);
      await button(tester, '添加来源');
      expect(tester.takeException(), isNull);
    });
  }
}
