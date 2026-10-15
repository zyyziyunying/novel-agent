import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/library_controller.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_gateway.dart';
import 'package:novel_workbench/src/library_workbench.dart';

import 'support/discussion_gateway.dart';

void main() {
  Future<(DiscussionGateway, LibraryController)> prepare(
    WidgetTester tester, {
    bool seed = true,
  }) async {
    final gateway = DiscussionGateway();
    gateway.workspace = LibraryWorkspace(
      revision: 0,
      works: gateway.workspace.works,
      libraries: [KnowledgeLibrary(id: 'k', name: '共享资料库', documents: [])],
      receipts: {},
    );
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    if (seed) {
      for (final workId in ['work-a', 'work-b']) {
        await controller.createDiscussion(
          workId,
          'talk',
          '$workId 的构思讨论',
          'chapter-1',
        );
      }
    }
    await tester.pumpWidget(
      MaterialApp(home: LibraryWorkbench(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('持续讨论'));
    await tester.pumpAndSettle();
    return (gateway, controller);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      80,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
    await tester.pumpAndSettle();
  }

  testWidgets('创建具名章节讨论，三轮交互和切换作品保持输入与记录', (tester) async {
    final (gateway, controller) = await prepare(tester, seed: false);
    await tester.tap(find.byTooltip('新建讨论'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '讨论名称'), '第一章审稿');
    await tester.tap(find.text('整部作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 章 · 第一章 · 雨夜来信').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建讨论'));
    await tester.pumpAndSettle();
    expect(
      gateway.workspace.work('work-a').discussions.single.chapterId,
      'chapter-1',
    );
    for (var i = 1; i <= 3; i++) {
      await tester.enterText(
        find.byKey(const ValueKey('discussion-input')),
        '第 $i 轮构思',
      );
      await tester.tap(find.text('发送新一轮'));
      await tester.pumpAndSettle();
    }
    expect(
      gateway.workspace.work('work-a').discussions.single.messages.length,
      6,
    );
    expect(gateway.workspace.work('work-b').discussions, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('discussion-input')),
      'A 未发送想法',
    );
    controller.select('work-b');
    await tester.pumpAndSettle();
    expect(find.text('A 未发送想法'), findsNothing);
    controller.select('work-a');
    await tester.pumpAndSettle();
    expect(find.text('A 未发送想法'), findsOneWidget);
    await tester.tap(find.byTooltip('返回正文'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('持续讨论'));
    await tester.pumpAndSettle();
    expect(find.text('A 未发送想法'), findsOneWidget);
  });

  testWidgets('迟到回复和错误仍属于原作品讨论；B 输入不受影响', (tester) async {
    final (gateway, controller) = await prepare(tester);
    gateway.replyRelease = Completer();
    await tester.enterText(
      find.byKey(const ValueKey('discussion-input')),
      'A 的异步要求',
    );
    await tester.tap(find.text('发送新一轮'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('discussion-input')))
          .readOnly,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('discussion-input')),
      'A 下一轮草稿',
    );
    controller.select('work-b');
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('discussion-input')),
      'B 保留草稿',
    );
    gateway.replyRelease!.complete();
    await tester.pumpAndSettle();
    expect(find.text('B 保留草稿'), findsOneWidget);
    expect(find.text('讨论建议：A 的异步要求'), findsNothing);
    controller.select('work-a');
    await tester.pumpAndSettle();
    expect(find.text('讨论建议：A 的异步要求'), findsOneWidget);
    expect(find.text('A 下一轮草稿'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('discussion-input')))
          .readOnly,
      isFalse,
    );
    gateway.replyRelease = null;
    gateway.failReply = true;
    await controller.sendDiscussion('work-a', 'talk', '会失败的原请求');
    controller.select('work-b');
    await tester.pumpAndSettle();
    expect(find.textContaining('模型调用失败'), findsNothing);
    controller.select('work-a');
    await tester.pumpAndSettle();
    expect(find.textContaining('模型调用失败'), findsWidgets);
    gateway.failReply = false;
    await scrollTo(tester, find.text('重试本轮'));
    await tester.tap(find.text('重试本轮'));
    await tester.pumpAndSettle();
    final sends = gateway.commands
        .where((c) => c.operation == 'sendDiscussionMessage')
        .toList();
    expect(sends.last.toJson(), sends[sends.length - 2].toJson());
    expect(
      gateway.workspace.work('work-a').discussions.single.messages.length,
      4,
    );
  });

  testWidgets('无模型回看已有回复并保存计划，来源和身份保留且不自动采用', (tester) async {
    final (gateway, controller) = await prepare(tester);
    await controller.sendDiscussion('work-a', 'talk', '未来情节');
    gateway.modelAvailable = false;
    await controller.load();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发送新一轮'))
          .onPressed,
      isNull,
    );
    await scrollTo(tester, find.text('保存到知识库').last);
    await tester.tap(find.text('保存到知识库').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('外部参考'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未来计划').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '资料标题'), '采用的情节计划');
    await tester.enterText(
      find.widgetWithText(TextField, '资料简介（description）'),
      '规划下一章情节时读取。',
    );
    await tester.enterText(find.widgetWithText(TextField, '标签（TAG）'), '情节，下一章');
    await tester.ensureVisible(find.text('必读资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('必读资料'));
    await tester.tap(find.text('保存成果'));
    await tester.pumpAndSettle();
    final doc = gateway.workspace.library('k').documents.single;
    expect(doc.current.kind, 'plan');
    expect(doc.current.description, '规划下一章情节时读取。');
    expect(doc.current.tags, ['情节', '下一章']);
    expect(doc.current.alwaysRead, isTrue);
    expect(doc.current.body, '讨论建议：未来情节');
    expect(doc.current.associatedWorkId, 'work-a');
    expect(
      (doc.current.provenance.sources.single as DiscussionSource).workId,
      'work-a',
    );
    expect(gateway.workspace.work('work-a').knowledgeLinks, isEmpty);
    expect(gateway.workspace.work('work-a').proposals, isEmpty);
    expect(gateway.commands.last.operation, 'adoptDiscussionMessage');
  });

  testWidgets('选择原文片段生成待接受提案，选段外保留且正文不立即改变', (tester) async {
    final (gateway, controller) = await prepare(tester);
    await controller.sendDiscussion('work-a', 'talk', '局部改稿');
    await tester.pumpAndSettle();
    final original = gateway.workspace.work('work-a').chapters.first.body;
    await scrollTo(tester, find.text('生成改稿提案').last);
    await tester.tap(find.text('生成改稿提案').last);
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(
      find.byKey(const ValueKey('discussion-original')),
    );
    editor.controller!.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 4,
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('discussion-result')),
      '作者选定替换',
    );
    await tester.tap(find.text('保存待接受提案'));
    await tester.pumpAndSettle();
    final proposal = gateway.workspace.work('work-a').proposals.single;
    expect(
      proposal.proposal.body,
      '${original.substring(0, 1)}作者选定替换${original.substring(4)}',
    );
    expect(proposal.proposal.status, 'pending');
    expect(proposal.discussionSource, isNotNull);
    expect(gateway.workspace.work('work-a').chapters.first.body, original);
  });

  testWidgets('采用来源冲突保留成果草稿并恢复可编辑状态', (tester) async {
    final (gateway, controller) = await prepare(tester);
    await controller.sendDiscussion('work-a', 'talk', '成果采用冲突');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('保存到知识库').last);
    await tester.tap(find.text('保存到知识库').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('discussion-result')),
      '作者整理的成果',
    );
    await controller.controllerFor('work-a').act('createChapter', {
      'chapterId': 'new-chapter',
      'title': '后续章',
    });
    await tester.tap(find.text('保存成果'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('讨论来源版本冲突'),
      ),
      findsOneWidget,
    );
    final editor = tester.widget<TextField>(
      find.byKey(const ValueKey('discussion-result')),
    );
    expect(editor.controller!.text, '作者整理的成果');
    expect(editor.readOnly, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('discussion-result')),
      '冲突后仍可编辑',
    );
    expect(find.text('冲突后仍可编辑'), findsOneWidget);
    expect(gateway.workspace.library('k').documents, isEmpty);
  });

  testWidgets('待完成回执不足以确认回复，刷新后保留原请求再重试', (tester) async {
    final (gateway, controller) = await prepare(tester);
    gateway.losePendingResponse = true;
    await controller.sendDiscussion('work-a', 'talk', '不重复作者消息');
    final original = controller.discussionState('work-a', 'talk').pending!;
    await controller.load();
    await tester.pumpAndSettle();
    expect(controller.discussionState('work-a', 'talk').pending, isNotNull);
    expect(controller.canChangeCatalog, isFalse);
    gateway.losePendingResponse = false;
    await controller.retryDiscussion('work-a', 'talk', original.requestId);
    await tester.pumpAndSettle();
    expect(controller.discussionState('work-a', 'talk').pending, isNull);
    expect(gateway.commands.last.toJson(), original.toJson());
    expect(
      gateway.workspace.work('work-a').discussions.single.messages.length,
      2,
    );
    expect(controller.canChangeCatalog, isTrue);
  });

  testWidgets('成果保存冲突留在发起作品，切换后可返回查看且保留讨论草稿', (tester) async {
    final (gateway, controller) = await prepare(tester);
    await controller.sendDiscussion('work-a', 'talk', '成果采用冲突');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('discussion-input')),
      'A 下一轮草稿',
    );
    await scrollTo(tester, find.text('保存到知识库').last);
    await tester.tap(find.text('保存到知识库').last);
    await tester.pumpAndSettle();
    await controller.controllerFor('work-a').act('createChapter', {
      'chapterId': 'changed-chapter',
      'title': '来源已改变',
    });
    await tester.tap(find.text('保存成果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('讨论来源版本冲突'), findsOneWidget);

    controller.select('work-b');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理知识库'));
    await tester.pumpAndSettle();
    expect(find.text('讨论来源版本冲突'), findsNothing);
    await tester.tap(find.byTooltip('持续讨论'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建讨论'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('讨论来源版本冲突'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作品 A：操作失败，返回查看'));
    await tester.pumpAndSettle();
    expect(controller.selectedId, 'work-a');
    expect(find.text('讨论来源版本冲突'), findsOneWidget);
    expect(find.text('A 下一轮草稿'), findsOneWidget);
    expect(gateway.workspace.library('k').documents, isEmpty);
  });

  testWidgets('已完成回执刷新后迟到网络失败不退回未知状态', (tester) async {
    final (gateway, controller) = await prepare(tester);
    final delayed = Completer<LibraryResult>();
    gateway.response = delayed;
    // The fixture commits synchronously before throwing; refresh the catalog before its catch runs.
    final sending = controller.sendDiscussion('work-a', 'talk', '已完成要求');
    await controller.load();
    delayed.completeError(const GatewayFailure('迟到的网络失败', uncertain: true));
    expect(await sending, isTrue);
    expect(controller.discussionState('work-a', 'talk').pending, isNull);
    expect(controller.discussionState('work-a', 'talk').error, isNull);
    expect(
      gateway.workspace.work('work-a').discussions.single.messages.length,
      2,
    );
  });

  for (final failed in [false, true]) {
    testWidgets('响应丢失后刷新${failed ? '失败' : '完成'}轮次，同步错误提示', (tester) async {
      final (gateway, controller) = await prepare(tester);
      gateway.failReply = failed;
      gateway.loseFinishedResponse = true;
      expect(
        await controller.sendDiscussion('work-a', 'talk', '刷新确认本轮'),
        isFalse,
      );
      await tester.pumpAndSettle();
      final state = controller.discussionState('work-a', 'talk');
      expect(state.busy, isFalse);
      expect(state.pending, isNotNull);
      expect(find.text('迟到网络失败'), findsOneWidget);
      expect(controller.canChangeCatalog, isFalse);

      await tester.tap(find.text('刷新讨论'));
      await tester.pumpAndSettle();
      expect(state.pending, isNull);
      expect(controller.canChangeCatalog, isTrue);
      expect(find.text('迟到网络失败'), findsNothing);
      expect(find.text('本轮结果待确认。'), findsNothing);
      expect(
        controller.workspace!
            .work('work-a')
            .discussions
            .single
            .turns
            .single
            .status,
        failed ? 'failed' : 'completed',
      );
      if (failed) {
        expect(state.error, discussionFailure('model_failed'));
        expect(find.text(discussionFailure('model_failed')), findsWidgets);
        expect(find.text('重试本轮'), findsOneWidget);
      } else {
        expect(state.error, isNull);
        expect(find.text('讨论建议：刷新确认本轮'), findsOneWidget);
      }
      expect(
        gateway.commands.where((c) => c.operation == 'sendDiscussionMessage'),
        hasLength(1),
      );
    });
  }

  testWidgets('空白关联章仍可选另一非空章生成改稿提案', (tester) async {
    final (gateway, controller) = await prepare(tester);
    await controller.controllerFor('work-a').act('createChapter', {
      'chapterId': 'blank',
      'title': '空白章',
    });
    await controller.createDiscussion('work-a', 'blank-talk', '空章构思', 'blank');
    controller.selectDiscussion('work-a', 'blank-talk');
    await controller.sendDiscussion('work-a', 'blank-talk', '已写章节改稿');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('生成改稿提案').last);
    await tester.tap(find.text('生成改稿提案').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第 1 章 · 第一章 · 雨夜来信'), findsOneWidget);
    expect(gateway.workspace.work('work-a').chapters.last.body, isEmpty);
  });

  testWidgets('讨论引用正文显示章节序号与本章历史版本', (tester) async {
    final (_, controller) = await prepare(tester);
    await controller.sendDiscussion('work-a', 'talk', '检查版本');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('查看本轮引用与版本'));
    await tester.tap(find.text('查看本轮引用与版本'));
    await tester.pumpAndSettle();
    expect(find.text('正文：第 1 章 · 第一章 · 雨夜来信 · 第 1 版'), findsOneWidget);
  });

  testWidgets('390 宽与 1.5 倍字号仍可发送、查看引用和采用成果', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (gateway, controller) = await prepare(tester);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: LibraryWorkbench(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await controller.sendDiscussion('work-a', 'talk', '窄屏讨论');
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('查看本轮引用与版本'));
    await tester.tap(find.text('查看本轮引用与版本'));
    await tester.pumpAndSettle();
    expect(find.text('本轮没有采用资料。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await scrollTo(tester, find.text('保存到知识库').last);
    await tester.tap(find.text('保存到知识库').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存成果'));
    await tester.tap(find.text('保存成果'));
    await tester.pumpAndSettle();
    expect(gateway.workspace.library('k').documents.length, 1);
    expect(tester.takeException(), isNull);
  });
}
