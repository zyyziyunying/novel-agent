import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/controller.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/workbench.dart';

void main() {
  Future<WorkspaceController> mount(
    WidgetTester tester,
    FakeGateway gateway, {
    Size size = const Size(1440, 1000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WorkspaceController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: NovelWorkbench(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('空工作区在 ${size.width} 宽度可打开并起草第一章', (tester) async {
      final gateway = FakeGateway()
        ..workspace = Workspace(
          revision: 0,
          title: '新作品',
          documents: [],
          chapters: [],
          proposals: [],
          memories: [],
          receipts: {},
        );
      await mount(tester, gateway, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('新作品'), findsOneWidget);
      expect(find.text('尚无正文'), findsOneWidget);
      if (size.width < 1120) {
        await tester.tap(find.byTooltip('知识库与写作助手'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('起草第一章'));
      await tester.pumpAndSettle();
      final instruction = find.widgetWithText(TextField, '作者要求');
      expect(
        tester.widget<TextField>(instruction).controller!.text,
        isNot(contains('林舟')),
      );
      await tester.enterText(instruction, '写一位航海者启程的第一章。');
      await tester.tap(find.text('生成提案'));
      await tester.pumpAndSettle();
      expect(gateway.commands.single.operation, 'proposeChapter');
      expect(gateway.commands.single.payload['instruction'], '写一位航海者启程的第一章。');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏显示正文、资料和记忆，保存正文传递作者草稿', (tester) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    expect(find.text('人物与叙述约束'), findsOneWidget);
    expect(find.text('记忆与当前正文版本一致'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      '作者保存的正文。',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(gateway.commands.single.operation, 'saveChapter');
    expect(gateway.commands.single.payload['body'], '作者保存的正文。');
    expect(find.text('有未保存草稿'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节版本按本章历史编号，恢复传原 ID，恢复后保存追加新序号', (tester) async {
    final gateway = FakeGateway();
    final original = gateway.workspace.chapters.first;
    final chapter = Chapter(
      id: original.id,
      number: 1,
      title: original.title,
      head: 'version-130',
      versions: const [
        TextVersion(id: 'version-11', body: '第一版正文'),
        TextVersion(id: 'version-58', body: '第二版正文'),
        TextVersion(id: 'version-130', body: '第三版正文'),
      ],
    );
    gateway.workspace = gateway.workspace.replace(
      revision: 130,
      chapters: [chapter, gateway.workspace.chapters[1]],
      memories: [],
    );
    await mount(tester, gateway);
    expect(find.text('已保存 · 第 3 版'), findsOneWidget);
    expect(find.textContaining('version-130'), findsNothing);
    await tester.tap(find.text('历史版本'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 版（当前）'), findsOneWidget);
    expect(find.text('恢复第 2 版'), findsOneWidget);
    await tester.tap(find.text('恢复第 1 版'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.payload, {
      'chapterId': chapter.id,
      'versionId': 'version-11',
    });
    expect(find.text('已保存 · 第 1 版'), findsOneWidget);
    expect(gateway.workspace.chapters.first.versions.length, 3);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('body-${chapter.id}')))
          .controller!
          .text,
      '第一版正文',
    );
    await tester.enterText(
      find.byKey(ValueKey('body-${chapter.id}')),
      '恢复后新写的正文',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(find.text('已保存 · 第 4 版'), findsOneWidget);
    expect(gateway.workspace.chapters.first.versions.length, 4);
    await tester.tap(find.text('历史版本'));
    await tester.pumpAndSettle();
    expect(find.text('恢复第 3 版'), findsOneWidget);
    await tester.tap(find.text('恢复第 3 版'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.payload['versionId'], 'version-130');
    expect(find.text('已保存 · 第 3 版'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节版本在记忆证据与提案上下文中显示对应章节的历史序号', (tester) async {
    final gateway = FakeGateway();
    final original = gateway.workspace.chapters.first;
    final chapter = Chapter(
      id: original.id,
      number: 1,
      title: original.title,
      head: 'version-90',
      versions: [
        TextVersion(id: 'version-4', body: original.body),
        TextVersion(id: 'version-37', body: original.body),
        TextVersion(id: 'version-90', body: original.body),
      ],
    );
    final chapters = [chapter, gateway.workspace.chapters[1]];
    gateway.workspace = gateway.workspace.replace(
      chapters: chapters,
      memories: [
        MemorySnapshot(
          id: 'test-memory',
          sourceHeads: {for (final c in chapters) c.id: c.head},
          facts: [
            for (final c in chapters)
              StoryFact(
                text: '测试事实',
                chapterId: c.id,
                versionId: c.head,
                evidence: c.body.substring(0, 2),
              ),
          ],
        ),
      ],
      proposals: [
        Proposal(
          id: 'test-proposal',
          chapterId: chapter.id,
          title: chapter.title,
          body: '待接受的修改提案',
          baseHeads: {chapter.id: 'version-37'},
          baseRevision: 37,
          status: 'pending',
          provider: 'fixture/local',
          context: {'authorInstruction': '修改开篇', 'documents': []},
          usage: {},
        ),
      ],
    );
    await mount(tester, gateway);
    final evidence = find.text('第 1 章 · ${chapter.title} · 第 3 版');
    await tester.ensureVisible(evidence);
    expect(evidence, findsOneWidget);
    await tester.ensureVisible(find.text('查看修改与上下文'));
    await tester.tap(find.text('查看修改与上下文'));
    await tester.pumpAndSettle();
    expect(find.text('正文版本：第 1 章 · ${chapter.title} · 第 2 版'), findsOneWidget);
    expect(find.textContaining('version-37'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同名章节来源在记忆与提案中按章节序号区分，事实证据仍属于原章节', (tester) async {
    final gateway = FakeGateway();
    final chapters = [
      for (var number = 1; number <= 2; number++)
        Chapter(
          id: 'chapter-$number',
          number: number,
          title: '重逢',
          head: 'chapter-$number-v2',
          versions: [
            TextVersion(id: 'chapter-$number-v1', body: '第 $number 章旧正文'),
            TextVersion(id: 'chapter-$number-v2', body: '第 $number 章当前正文'),
          ],
        ),
    ];
    final sourceHeads = {for (final c in chapters) c.id: c.head};
    gateway.workspace = gateway.workspace.replace(
      chapters: chapters,
      memories: [
        MemorySnapshot(
          id: 'same-title-memory',
          sourceHeads: sourceHeads,
          facts: [
            for (final c in chapters)
              StoryFact(
                text: '第 ${c.number} 章事实',
                chapterId: c.id,
                versionId: c.head,
                evidence: c.body,
              ),
          ],
        ),
      ],
      proposals: [
        Proposal(
          id: 'same-title-proposal',
          chapterId: chapters.first.id,
          title: '重逢',
          body: '待接受的修改',
          baseHeads: sourceHeads,
          baseRevision: 0,
          status: 'pending',
          provider: 'fixture/local',
          context: {'authorInstruction': '检查来源', 'documents': []},
          usage: {},
        ),
      ],
    );
    await mount(tester, gateway);
    for (final chapter in chapters) {
      final label = find.text('第 ${chapter.number} 章 · 重逢 · 第 2 版');
      expect(label, findsOneWidget);
      final evidenceBlock = find
          .ancestor(of: label, matching: find.byType(Column))
          .first;
      expect(
        find.descendant(
          of: evidenceBlock,
          matching: find.text('第 ${chapter.number} 章事实'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: evidenceBlock,
          matching: find.text('原文：“${chapter.body}”'),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('重逢 · 第 2 版'), findsNothing);
    await tester.ensureVisible(find.text('查看修改与上下文'));
    await tester.tap(find.text('查看修改与上下文'));
    await tester.pumpAndSettle();
    expect(find.text('正文版本：第 1 章 · 重逢 · 第 2 版'), findsOneWidget);
    expect(find.text('正文版本：第 2 章 · 重逢 · 第 2 版'), findsOneWidget);
    expect(gateway.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选段改稿先显示提案，拒绝后原文保持不变', (tester) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    final body = tester.widget<TextField>(
      find.byKey(const ValueKey('body-chapter-1')),
    );
    final original = body.controller!.text;
    final start = original.indexOf('信纸');
    final end = original.indexOf('\n\n他没有');
    body.controller!.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
    await tester.pump();
    await tester.tap(find.text('改写选段').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('生成提案'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(gateway.commands.first.payload['start'], start);
    expect(gateway.commands.first.payload['end'], end);
    expect(body.controller!.text, original);
    await tester.tap(find.text('查看修改与上下文'));
    await tester.pumpAndSettle();
    expect(find.text('修改前'), findsOneWidget);
    expect(find.text('提案正文'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.operation, 'rejectProposal');
    expect(body.controller!.text, original);
    expect(find.text('拒绝'), findsNothing);
  });

  testWidgets('刷新冲突保留未保存草稿，不能覆盖新版本', (tester) async {
    final gateway = FakeGateway();
    final controller = await mount(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      '本地尚未保存的草稿。',
    );
    gateway.workspace = gateway.workspace.replace(
      chapters: [
        gateway.workspace.chapters.first.replace(
          head: 'external',
          versions: [
            ...gateway.workspace.chapters.first.versions,
            const TextVersion(id: 'external', body: '另一个客户端保存的新版本。'),
          ],
        ),
        gateway.workspace.chapters[1],
      ],
    );
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('body-chapter-1')),
    );
    expect(field.controller!.text, '本地尚未保存的草稿。');
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存正文').first,
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('切换章节后仍保留未保存草稿', (tester) async {
    await mount(tester, FakeGateway());
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      '未保存草稿。',
    );
    await tester.tap(find.text('第二章 · 门外的人').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一章 · 雨夜来信').first);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('body-chapter-1')),
    );
    expect(field.controller!.text, '未保存草稿。');
  });

  testWidgets('窄屏和大字号仍可编辑并打开助手', (tester) async {
    await mount(
      tester,
      FakeGateway(),
      size: const Size(390, 844),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('知识库与写作助手'));
    await tester.pumpAndSettle();
    expect(find.text('写作助手'), findsOneWidget);
    expect(find.text('起草下一章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS 紧凑助手提供路由名称，关闭后恢复正文语义', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, FakeGateway(), size: const Size(1024, 640));
      await tester.tap(find.byTooltip('知识库与写作助手'));
      await tester.pumpAndSettle();
      final routes = find.semantics
          .byFlag(SemanticsFlag.scopesRoute)
          .evaluate()
          .where((node) => node.getSemanticsData().flagsCollection.namesRoute);
      expect(routes.map((node) => node.label), contains('知识库与写作助手'));
      expect(
        find.semantics
            .byLabel('知识库与写作助手')
            .evaluate()
            .single
            .getSemanticsData()
            .role,
        SemanticsRole.dialog,
      );
      expect(routes.every((node) => node.label.trim().isNotEmpty), isTrue);
      expect(find.text('写作助手'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('知识库与写作助手'), findsOneWidget);
      expect(find.byKey(const ValueKey('body-chapter-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('结果未知时重试复用同一请求，并暂时阻止其他修改', () async {
    final gateway = FakeGateway()..failUncertain = true;
    final controller = WorkspaceController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.act('rebuildMemory');
    final id = controller.pending!.requestId;
    await controller.act('saveChapter', {
      'chapterId': 'chapter-1',
      'body': '不能提交',
    });
    expect(gateway.commands, hasLength(1));
    gateway.failUncertain = false;
    await controller.retry();
    expect(gateway.commands.last.requestId, id);
    expect(controller.pending, isNull);
  });

  testWidgets('跨越宽窄布局断点保留所有章节草稿和选区', (tester) async {
    await mount(tester, FakeGateway());
    final first = find.byKey(const ValueKey('body-chapter-1'));
    await tester.enterText(first, '第一章不可丢失的草稿');
    final selection = const TextSelection(baseOffset: 2, extentOffset: 6);
    tester.widget<TextField>(first).controller!.selection = selection;
    await tester.tap(find.text('第二章 · 门外的人').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-2')),
      '第二章不可丢失的草稿',
    );
    for (final size in [const Size(1000, 1000), const Size(1440, 1000)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('body-chapter-2')))
          .controller!
          .text,
      '第二章不可丢失的草稿',
    );
    await tester.tap(find.text('第一章 · 雨夜来信').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(first).controller!.text, '第一章不可丢失的草稿');
    expect(tester.widget<TextField>(first).controller!.selection, selection);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未知请求刷新无回执后仍可用原请求重试', (tester) async {
    final gateway = FakeGateway()..failUncertain = true;
    final controller = await mount(tester, gateway);
    await controller.act('rebuildMemory');
    final id = controller.pending!.requestId;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新作品'));
    await tester.pumpAndSettle();
    expect(controller.error, isNull);
    expect(controller.pending!.requestId, id);
    expect(find.text('重试上次操作'), findsOneWidget);
    gateway.failUncertain = false;
    await tester.tap(find.text('重试上次操作'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.requestId, id);
    expect(controller.pending, isNull);
    expect(find.text('重试上次操作'), findsNothing);
  });

  testWidgets('后台忙碌时资料保存禁用，完成后仍可保存原草稿', (tester) async {
    final gateway = FakeGateway()..gate = Completer<void>();
    final controller = await mount(tester, gateway);
    final action = controller.act('rebuildMemory');
    await tester.pump();
    await tester.tap(find.text('人物与叙述约束'));
    await tester.pump(const Duration(milliseconds: 300));
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.last, '后台忙碌时仍需保留的作者设定');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存资料'))
          .onPressed,
      isNull,
    );
    expect(gateway.commands.map((c) => c.operation), ['rebuildMemory']);
    gateway.gate!.complete();
    await action;
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(fields.last).controller!.text,
      '后台忙碌时仍需保留的作者设定',
    );
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.workspace.documents.last.body, '后台忙碌时仍需保留的作者设定');
  });

  testWidgets('资料保存被拒绝后保留标题正文身份，刷新后可再次保存', (tester) async {
    final gateway = FakeGateway()..failDefinite = true;
    await mount(tester, gateway);
    await tester.tap(find.text('人物与叙述约束'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '作者改过的标题');
    await tester.enterText(fields.last, '拒绝后不可丢失的设定');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未来计划').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('模拟版本冲突')),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(fields.first).controller!.text, '作者改过的标题');
    expect(
      tester.widget<TextField>(fields.last).controller!.text,
      '拒绝后不可丢失的设定',
    );
    gateway.failDefinite = false;
    await tester.tap(find.widgetWithText(TextButton, '刷新作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final document = gateway.workspace.documents.last;
    expect(document.title, '作者改过的标题');
    expect(document.body, '拒绝后不可丢失的设定');
    expect(document.kind, 'plan');
  });

  for (final changedField in ['title', 'kind', 'body']) {
    testWidgets('资料 $changedField 被其他标签改动，刷新保留草稿并阻止覆盖', (tester) async {
      final gateway = FakeGateway();
      await mount(tester, gateway);
      await tester.tap(find.text('人物与叙述约束'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, '本地标题草稿');
      await tester.enterText(fields.last, '基于旧资料编辑的本地草稿');
      final original = gateway.workspace.documents.first;
      final latest = SourceDocument.fromJson({
        ...original.toJson(),
        changedField: switch (changedField) {
          'title' => '其他标签保存的标题',
          'kind' => 'plan',
          _ => '其他标签保存的新设定',
        },
      });
      gateway.workspace = gateway.workspace.replace(
        revision: gateway.workspace.revision + 1,
        documents: [
          for (final document in gateway.workspace.documents)
            if (document.id == latest.id) latest else document,
        ],
      );
      await tester.tap(find.text('保存资料'));
      await tester.pumpAndSettle();
      expect(find.text('模拟版本冲突'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, '刷新作品'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.first).controller!.text, '本地标题草稿');
      expect(
        tester.widget<TextField>(fields.last).controller!.text,
        '基于旧资料编辑的本地草稿',
      );
      expect(find.text('服务端资料已变化，当前草稿已保留。请查看新版资料后再决定。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存资料'))
            .onPressed,
        isNull,
      );
      expect(gateway.commands, hasLength(1));
      expect(
        gateway.workspace.documents
            .firstWhere((d) => d.id == latest.id)
            .toJson(),
        latest.toJson(),
      );
      await tester.ensureVisible(find.text('查看新版资料'));
      await tester.tap(find.text('查看新版资料'));
      await tester.pumpAndSettle();
      expect(find.text('新版标题：${latest.title}'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(latest.body),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('放弃草稿并加载新版资料'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        latest.title,
      );
      expect(
        tester.widget<TextField>(fields.last).controller!.text,
        latest.body,
      );
      expect(find.text('查看新版资料'), findsNothing);
      await tester.enterText(fields.last, '作者查看新版后重新编辑的设定');
      await tester.tap(find.text('保存资料'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final saved = gateway.workspace.documents.firstWhere(
        (d) => d.id == latest.id,
      );
      expect(saved.body, '作者查看新版后重新编辑的设定');
      expect(saved.title, latest.title);
      expect(saved.kind, latest.kind);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('仅其他章节变化，资料冲突刷新后仍可保存原草稿', (tester) async {
    final gateway = FakeGateway();
    await mount(tester, gateway);
    await tester.tap(find.text('人物与叙述约束'));
    await tester.pumpAndSettle();
    final body = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .last;
    await tester.enterText(body, '资料来源未变化的作者草稿');
    // A different tab advances the workspace without changing this document.
    await gateway.execute(
      NovelCommand(
        requestId: 'other-tab-chapter-save',
        expectedRevision: gateway.workspace.revision,
        operation: 'saveChapter',
        payload: {'chapterId': 'chapter-2', 'body': '另一标签保存的第二章'},
      ),
    );
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.text('模拟版本冲突'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '刷新作品'));
    await tester.pumpAndSettle();
    expect(find.text('查看新版资料'), findsNothing);
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.workspace.documents.last.body, '资料来源未变化的作者草稿');
    expect(gateway.workspace.chapters[1].body, '另一标签保存的第二章');
    expect(tester.takeException(), isNull);
  });

  testWidgets('提案预览跨越宽窄布局断点后仍能关闭', (tester) async {
    final gateway = FakeGateway();
    final controller = await mount(tester, gateway);
    await controller.act('proposeEdit', {
      'chapterId': 'chapter-1',
      'start': 0,
      'end': 2,
      'instruction': '改写开头',
    });
    await tester.pumpAndSettle();
    final originalBody = gateway.workspace.chapters.first.body;
    await tester.tap(find.text('查看修改与上下文'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(900, 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(NovelWorkbench), findsOneWidget);
    expect(gateway.workspace.proposals.single.status, 'pending');
    expect(gateway.workspace.chapters.first.body, originalBody);
  });

  for (final confirmation in ['retry', 'receipt']) {
    testWidgets('资料结果未知后通过 $confirmation 确认保存才关闭表单', (tester) async {
      final gateway = FakeGateway()..failUncertain = true;
      final controller = await mount(tester, gateway);
      await tester.tap(find.text('人物与叙述约束'));
      await tester.pumpAndSettle();
      final body = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .last;
      await tester.enterText(body, '等待确认的设定');
      await tester.tap(find.text('保存资料'));
      await tester.pumpAndSettle();
      final pending = controller.pending!;
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TextField>(body).controller!.text, '等待确认的设定');
      expect(tester.widget<TextField>(body).readOnly, isTrue);
      // A successful refresh without a receipt must not close or unlock it.
      await tester.tap(find.widgetWithText(TextButton, '刷新作品'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('重试上次操作'),
        ),
        findsOneWidget,
      );
      gateway.failUncertain = false;
      if (confirmation == 'retry') {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('重试上次操作'),
          ),
        );
      } else {
        await gateway.execute(pending);
        await tester.tap(find.widgetWithText(TextButton, '刷新作品'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.pending, isNull);
      expect(gateway.commands.last.requestId, pending.requestId);
      expect(gateway.workspace.documents.last.body, '等待确认的设定');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('关闭未知结果资料表单后确认回执，不会退出工作台', (tester) async {
    final gateway = FakeGateway()..failUncertain = true;
    final controller = await mount(tester, gateway);
    await tester.tap(find.text('人物与叙述约束'));
    await tester.pumpAndSettle();
    final body = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        )
        .last;
    await tester.enterText(body, '已提交等待确认的资料');
    await tester.tap(find.text('保存资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pump();
    gateway.failUncertain = false;
    await controller.retry();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(NovelWorkbench), findsOneWidget);
    expect(find.byKey(const ValueKey('body-chapter-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存等待期间继续输入，成功后保留并能保存后续草稿', (tester) async {
    final gateway = FakeGateway()..gate = Completer<void>();
    await mount(tester, gateway);
    final field = find.byKey(const ValueKey('body-chapter-1'));
    await tester.enterText(field, '保存内容 A');
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pump();
    await tester.enterText(field, '继续编辑 B');
    gateway.gate!.complete();
    await tester.pumpAndSettle();
    expect(gateway.workspace.chapters.first.body, '保存内容 A');
    expect(tester.widget<TextField>(field).controller!.text, '继续编辑 B');
    expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(gateway.workspace.chapters.first.body, '继续编辑 B');
    expect(find.text('有未保存草稿'), findsNothing);
  });

  for (final confirmation in ['retry', 'receipt']) {
    testWidgets('正文未知保存通过 $confirmation 确认后保留后续输入', (tester) async {
      final gateway = FakeGateway()..failUncertain = true;
      final controller = await mount(tester, gateway);
      final field = find.byKey(const ValueKey('body-chapter-1'));
      await tester.enterText(field, '保存内容 A');
      await tester.pump();
      await tester.tap(find.text('保存正文').first);
      await tester.pumpAndSettle();
      final pending = controller.pending!;
      await tester.enterText(field, '继续编辑 B');
      gateway.failUncertain = false;
      if (confirmation == 'retry') {
        await tester.tap(find.text('重试上次操作'));
      } else {
        await gateway.execute(pending);
        await tester.tap(find.byTooltip('刷新作品'));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '继续编辑 B');
      expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
      await tester.tap(find.text('保存正文').first);
      await tester.pumpAndSettle();
      expect(gateway.workspace.chapters.first.body, '继续编辑 B');
    });
  }

  for (final confirmation in ['direct', 'retry', 'receipt']) {
    testWidgets('等待 $confirmation 保存确认期间撤回到原文仍保留作者输入', (tester) async {
      final gateway = FakeGateway();
      if (confirmation == 'direct') {
        gateway.gate = Completer<void>();
      } else {
        gateway.failUncertain = true;
      }
      final original = gateway.workspace.chapters.first.body;
      final controller = await mount(tester, gateway);
      final field = find.byKey(const ValueKey('body-chapter-1'));
      await tester.enterText(field, '已经提交的 A');
      await tester.pump();
      await tester.tap(find.text('保存正文').first);
      if (confirmation == 'direct') {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }
      await tester.enterText(field, original);
      if (confirmation == 'direct') {
        gateway.gate!.complete();
      } else {
        gateway.failUncertain = false;
        if (confirmation == 'retry') {
          await controller.retry();
        } else {
          await gateway.execute(controller.pending!);
          await controller.load();
        }
      }
      await tester.pumpAndSettle();
      expect(gateway.workspace.chapters.first.body, '已经提交的 A');
      expect(tester.widget<TextField>(field).controller!.text, original);
      expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
      await tester.tap(find.text('保存正文').first);
      await tester.pumpAndSettle();
      expect(gateway.workspace.chapters.first.body, original);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('迟到回执之后已有外部版本，撤回草稿仍保留且冲突可见', (tester) async {
    final gateway = FakeGateway()..failUncertain = true;
    final original = gateway.workspace.chapters.first.body;
    final controller = await mount(tester, gateway);
    final field = find.byKey(const ValueKey('body-chapter-1'));
    await tester.enterText(field, '已经提交的 A');
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    await tester.enterText(field, original);
    gateway.failUncertain = false;
    await gateway.execute(controller.pending!);
    gateway.workspace = gateway.workspace.replace(
      revision: gateway.workspace.revision + 1,
      chapters: [
        gateway.workspace.chapters.first.replace(
          head: 'external',
          versions: [
            ...gateway.workspace.chapters.first.versions,
            const TextVersion(id: 'external', body: '后来的外部稿件 C'),
          ],
        ),
        gateway.workspace.chapters[1],
      ],
    );
    for (var i = 0; i < 2; i++) {
      await controller.load();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, original);
      expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '保存正文').first,
            )
            .onPressed,
        isNull,
      );
    }
    expect(gateway.workspace.chapters.first.body, '后来的外部稿件 C');
  });

  for (final empty in ['', ' \n ']) {
    testWidgets('空正文 $empty 显示校验并禁止提交', (tester) async {
      final gateway = FakeGateway();
      await mount(tester, gateway);
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-1')),
        empty,
      );
      await tester.pump();
      expect(find.text('正文不能为空。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '保存正文').first,
            )
            .onPressed,
        isNull,
      );
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  test('命令契约异常显示错误并允许修正后提交', () async {
    final gateway = FakeGateway();
    final controller = WorkspaceController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    expect(
      await controller.act('saveChapter', {
        'chapterId': 'chapter-1',
        'body': '',
      }),
      isFalse,
    );
    expect(controller.error, '输入内容不符合工作台要求，请检查后重试。');
    expect(controller.busy, isFalse);
    expect(controller.pending, isNull);
    expect(gateway.commands, isEmpty);
    expect(
      await controller.act('saveChapter', {
        'chapterId': 'chapter-1',
        'body': '有效正文。',
      }),
      isTrue,
    );
    expect(controller.error, isNull);
    expect(gateway.workspace.chapters.first.body, '有效正文。');
  });
}

class FakeGateway implements NovelGateway {
  Workspace workspace = demoWorkspace();
  final List<NovelCommand> commands = [];
  bool failUncertain = false;
  bool failDefinite = false;
  Completer<void>? gate;
  @override
  Future<WorkspaceResult> load() async =>
      WorkspaceResult(workspace, 'fixture/local');
  @override
  Future<WorkspaceResult> execute(NovelCommand command) async {
    commands.add(command);
    if (gate != null) await gate!.future;
    if (failUncertain) throw const GatewayFailure('模拟连接中断', uncertain: true);
    if (failDefinite) throw const GatewayFailure('模拟版本冲突');
    if (command.expectedRevision != workspace.revision) {
      throw const GatewayFailure('模拟版本冲突');
    }
    final payload = command.payload;
    if (command.operation == 'saveChapter') {
      workspace = workspace.replace(
        chapters: [
          for (final c in workspace.chapters)
            if (c.id == payload['chapterId'])
              c.replace(
                head: 'saved-${workspace.revision + 1}',
                versions: [
                  ...c.versions,
                  TextVersion(
                    id: 'saved-${workspace.revision + 1}',
                    body: payload['body'],
                  ),
                ],
              )
            else
              c,
        ],
      );
    } else if (command.operation == 'restoreVersion') {
      workspace = workspace.replace(
        chapters: [
          for (final c in workspace.chapters)
            c.id == payload['chapterId']
                ? c.replace(head: payload['versionId'])
                : c,
        ],
      );
    } else if (command.operation == 'proposeEdit') {
      final chapter = workspace.chapters.first;
      workspace = workspace.replace(
        proposals: [
          Proposal(
            id: 'test-proposal',
            chapterId: chapter.id,
            title: chapter.title,
            body: chapter.body.replaceRange(
              payload['start'],
              payload['end'],
              '替换选段。',
            ),
            baseHeads: workspace.currentHeads,
            baseRevision: workspace.revision,
            status: 'pending',
            provider: 'fixture/local',
            context: {
              'documents': [],
              'authorInstruction': payload['instruction'],
              'memory': workspace.currentMemory!.toJson(),
            },
            usage: {},
          ),
        ],
      );
    } else if (command.operation == 'rejectProposal') {
      workspace = workspace.replace(
        proposals: [for (final p in workspace.proposals) p.decide('rejected')],
      );
    } else if (command.operation == 'saveDocument') {
      workspace = workspace.replace(
        documents: [
          for (final d in workspace.documents)
            if (d.id != payload['id']) d,
          SourceDocument.fromJson(payload),
        ],
      );
    }
    final revision = workspace.revision + 1;
    workspace = workspace.replace(
      revision: revision,
      receipts: {
        ...workspace.receipts,
        command.requestId: Receipt(fingerprint: 'test', revision: revision),
      },
    );
    return WorkspaceResult(workspace, 'fixture/local');
  }

  @override
  void close() {}
}
