import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_controller.dart';
import 'package:novel_workbench/src/library_gateway.dart';
import 'package:novel_workbench/src/library_workbench.dart';

import 'support/library_gateway.dart';

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
        theme: ThemeData(useMaterial3: true),
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
    return controller;
  }

  Future<void> switchWork(WidgetTester tester, String title) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  TextEditingController body(WidgetTester tester, [String id = 'chapter-1']) =>
      tester.widget<TextField>(find.byKey(ValueKey('body-$id'))).controller!;

  Future<void> secondChapter(WidgetTester tester, Size size) async {
    if (size.width >= 1120) {
      await tester.tap(find.text('第二章 · 门外的人').first);
    } else {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二章 · 门外的人').last);
    }
    await tester.pumpAndSettle();
  }

  Future<void> openCreateChapter(WidgetTester tester, Size size) async {
    await tester.tap(
      size.width >= 1120 ? find.text('新建章节') : find.byTooltip('新建章节'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('章节版本在两作品和不同章节间独立递增，目录命名不改变版本显示', (tester) async {
    final gateway = FakeLibraryGateway();
    NovelWork workWithHistory(
      String id,
      String title,
      List<TextVersion> history,
    ) {
      final work = gateway.workspace.work(id);
      final first = work.chapters.first;
      return NovelWork(
        id: id,
        title: title,
        knowledgeLinks: [],
        chapters: [
          Chapter(
            id: first.id,
            number: 1,
            title: first.title,
            head: history.last.id,
            versions: history,
          ),
          work.chapters[1],
        ],
        proposals: [],
        memories: [],
        discussions: [],
      );
    }

    gateway.workspace = LibraryWorkspace(
      revision: 100,
      works: [
        workWithHistory('work-a', '作品 A', const [
          TextVersion(id: 'version-3', body: 'A 第一版'),
          TextVersion(id: 'version-35', body: 'A 第二版'),
        ]),
        workWithHistory('work-b', '作品 B', const [
          TextVersion(id: 'version-99', body: 'B 第一版'),
        ]),
      ],
      libraries: [],
      receipts: {},
    );
    final controller = await mount(tester, gateway);
    expect(find.text('已保存 · 第 2 版'), findsOneWidget);
    await switchWork(tester, '作品 B');
    expect(find.text('已保存 · 第 1 版'), findsOneWidget);
    await controller.renameWork('work-b', '作品 B 新名');
    await tester.pumpAndSettle();
    expect(find.text('已保存 · 第 1 版'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'B 第二版',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(find.text('已保存 · 第 2 版'), findsOneWidget);
    await switchWork(tester, '作品 A');
    expect(find.text('已保存 · 第 2 版'), findsOneWidget);
    expect(body(tester).text, 'A 第二版');
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 第三版',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(find.text('已保存 · 第 3 版'), findsOneWidget);
    await secondChapter(tester, const Size(1440, 1000));
    expect(find.text('已保存 · 第 1 版'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('在 ${size.width} 宽度手动创建首章，空标题被拦截，手写正文与草稿不串作品', (tester) async {
      final gateway = FakeLibraryGateway();
      gateway.workspace = LibraryWorkspace(
        revision: 0,
        works: [
          NovelWork(
            id: 'work-a',
            title: '作品 A',
            knowledgeLinks: [],
            chapters: [],
            proposals: [],
            memories: [],
            discussions: [],
          ),
          gateway.workspace.work('work-b'),
        ],
        libraries: [],
        receipts: {},
      );
      await mount(tester, gateway, size: size);
      await openCreateChapter(tester, size);
      final title = find.widgetWithText(TextField, '章节标题');
      await tester.enterText(title, '  ');
      await tester.tap(find.text('创建章节'));
      await tester.pumpAndSettle();
      expect(find.text('章节标题不能为空。'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      await tester.enterText(title, '我的第一章');
      await tester.tap(find.text('创建章节'));
      await tester.pumpAndSettle();
      final id = gateway.workspace.work('work-a').chapters.single.id;
      expect(body(tester, id).text, isEmpty);
      expect(gateway.commands.single.operation, 'createChapter');
      expect(gateway.commands.single.target.workId, 'work-a');
      await tester.enterText(find.byKey(ValueKey('body-$id')), '我亲自写的第一章。');
      await tester.pump();
      await tester.tap(find.text('保存正文').first);
      await tester.pumpAndSettle();
      expect(
        gateway.workspace.work('work-a').chapters.single.body,
        '我亲自写的第一章。',
      );
      await tester.enterText(find.byKey(ValueKey('body-$id')), '继续写但尚未保存');
      await switchWork(tester, '作品 B');
      expect(body(tester).text, isNot('继续写但尚未保存'));
      await switchWork(tester, '作品 A');
      expect(body(tester, id).text, '继续写但尚未保存');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('已有正文草稿时新建章节自动选中新章，旧章节草稿仍保留', (tester) async {
    final gateway = FakeLibraryGateway();
    await mount(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      '旧章未保存',
    );
    await openCreateChapter(tester, const Size(1440, 1000));
    await tester.enterText(find.widgetWithText(TextField, '章节标题'), '第三章 手写');
    await tester.tap(find.text('创建章节'));
    await tester.pumpAndSettle();
    final id = gateway.workspace.work('work-a').chapters.last.id;
    expect(find.byKey(ValueKey('body-$id')), findsOneWidget);
    expect(body(tester, id).text, isEmpty);
    expect(find.text('请先填写并保存空白章节，再重建记忆或起草下一章。'), findsOneWidget);
    await tester.tap(find.text('第一章 · 雨夜来信').first);
    await tester.pumpAndSettle();
    expect(body(tester).text, '旧章未保存');
  });

  testWidgets('创建已提交但响应丢失时保留标题，原请求重试不重复建章', (tester) async {
    final gateway = FakeLibraryGateway()
      ..failure = const GatewayFailure('连接中断', uncertain: true)
      ..commitBeforeFailure = true;
    await mount(tester, gateway);
    await openCreateChapter(tester, const Size(1440, 1000));
    await tester.enterText(find.widgetWithText(TextField, '章节标题'), '重试的章节');
    await tester.tap(find.text('创建章节'));
    await tester.pumpAndSettle();
    expect(find.text('结果尚未确认，标题已保留。请刷新或重试。'), findsOneWidget);
    expect(gateway.workspace.work('work-a').chapters.length, 3);
    final original = gateway.commands.single;
    gateway.failure = null;
    await tester.tap(find.text('重试章节操作'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.canonical, original.canonical);
    expect(gateway.workspace.work('work-a').chapters.length, 3);
    expect(find.byType(AlertDialog), findsNothing);
    expect(body(tester, original.payload['chapterId']).text, isEmpty);
  });

  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('两作品相同章节 ID 的草稿、选区和章节选择在 ${size.width} 宽度保持独立', (tester) async {
      await mount(tester, FakeLibraryGateway(), size: size);
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-1')),
        'A 未保存草稿',
      );
      body(tester).selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      await switchWork(tester, '作品 B');
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-1')),
        'B 未保存草稿',
      );
      await switchWork(tester, '作品 A');
      expect(body(tester).text, 'A 未保存草稿');
      expect(
        body(tester).selection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      await secondChapter(tester, size);
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-2')),
        'A 第二章草稿',
      );
      await switchWork(tester, '作品 B');
      expect(body(tester).text, 'B 未保存草稿');
      await switchWork(tester, '作品 A');
      expect(body(tester, 'chapter-2').text, 'A 第二章草稿');
      await switchWork(tester, '作品 B');
      tester.view.physicalSize = size.width > 1120
          ? const Size(390, 844)
          : const Size(1440, 1000);
      await tester.pumpAndSettle();
      expect(body(tester).text, 'B 未保存草稿');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('空目录创建两部具名作品、重命名并切换；名称从保存快照重新加载', (tester) async {
    final gateway = FakeLibraryGateway()
      ..workspace = LibraryWorkspace(
        revision: 0,
        works: [],
        libraries: [],
        receipts: {},
      );
    final controller = await mount(tester, gateway);
    for (final name in ['航海记', '长安夜']) {
      await tester.tap(find.byTooltip('创建作品'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '作品名称'), name);
      await tester.tap(find.text('保存名称'));
      await tester.pumpAndSettle();
      expect(find.text('尚无正文'), findsOneWidget);
    }
    final firstId = gateway.workspace.works.first.id;
    await switchWork(tester, '航海记');
    await tester.tap(find.byTooltip('重命名作品'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '作品名称'), '远航记');
    await tester.tap(find.text('保存名称'));
    await tester.pumpAndSettle();
    expect(gateway.commands.last.target.workId, firstId);
    expect(controller.selectedId, firstId);
    await controller.load();
    await tester.pumpAndSettle();
    expect(gateway.workspace.works.map((w) => w.title), ['远航记', '长安夜']);
    expect(find.text('远航记'), findsOneWidget);
  });

  testWidgets('A 保存等待期间切 B 编辑，迟到成功不替换 B 草稿；返回 A 保留后续输入', (tester) async {
    final gateway = FakeLibraryGateway()..response = Completer<LibraryResult>();
    await mount(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 保存正文',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 后续输入',
    );
    // Avoid settling an indeterminate progress indicator while A is busy.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('作品 B').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'B 草稿',
    );
    gateway.response!.complete(gateway.result());
    await tester.pumpAndSettle();
    expect(body(tester).text, 'B 草稿');
    expect(gateway.commands.single.target.workId, 'work-a');
    await switchWork(tester, '作品 A');
    expect(body(tester).text, 'A 后续输入');
    expect(find.text('有未保存草稿'), findsOneWidget);
    expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
  });

  for (final uncertain in [false, true]) {
    testWidgets('A ${uncertain ? '未知结果重试' : '确定失败'}绑定 A；B 的草稿保留', (
      tester,
    ) async {
      final gateway = FakeLibraryGateway()
        ..response = Completer<LibraryResult>();
      final controller = await mount(tester, gateway);
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-1')),
        'A 保存',
      );
      await tester.pump();
      await tester.tap(find.text('保存正文').first);
      await tester.pump();
      controller.select('work-b');
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('body-chapter-1')),
        'B 草稿',
      );
      gateway.response!.completeError(
        GatewayFailure(uncertain ? '结果未知 A' : '版本冲突 A', uncertain: uncertain),
      );
      await tester.pumpAndSettle();
      expect(body(tester).text, 'B 草稿');
      expect(controller.controllerFor('work-b').error, isNull);
      expect(controller.controllerFor('work-a').error, contains('A'));
      if (uncertain) {
        gateway.response = null;
        expect(await controller.controllerFor('work-a').retry(), isTrue);
        await tester.pumpAndSettle();
        expect(gateway.commands.last.toJson(), gateway.commands.first.toJson());
        expect(controller.selectedId, 'work-b');
        expect(body(tester).text, 'B 草稿');
      }
    });
  }

  testWidgets('后台生成提案只出现在 A；切换后 B 不显示 A 的提案或错误', (tester) async {
    final gateway = FakeLibraryGateway()..response = Completer<LibraryResult>();
    final controller = await mount(tester, gateway);
    final generating = controller.controllerFor('work-a').act(
      'proposeChapter',
      {'instruction': 'A 新章'},
    );
    controller.select('work-b');
    await tester.pump();
    gateway.response!.complete(gateway.result());
    await generating;
    await tester.pumpAndSettle();
    expect(find.text('作品 A 的提案'), findsNothing);
    await switchWork(tester, '作品 A');
    expect(find.text('作品 A 的提案'), findsOneWidget);
    expect(controller.controllerFor('work-b').workspace!.proposals, isEmpty);
  });

  testWidgets('窄屏大字号作品选择和命名入口无溢出', (tester) async {
    await mount(
      tester,
      FakeLibraryGateway(),
      size: const Size(390, 844),
      scale: 1.5,
    );
    await switchWork(tester, '作品 B');
    await tester.tap(find.byTooltip('重命名作品'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '作品名称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('查看 B 时刷新确认 A 保存回执，A 后续输入和 B 草稿均保留', (tester) async {
    final gateway = FakeLibraryGateway()
      ..failure = const GatewayFailure('A 结果未知', uncertain: true)
      ..commitBeforeFailure = true;
    final controller = await mount(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 已提交',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 后续草稿',
    );
    await switchWork(tester, '作品 B');
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'B 草稿',
    );
    await controller.load();
    await tester.pumpAndSettle();
    expect(controller.controllerFor('work-a').pending, isNull);
    expect(controller.controllerFor('work-a').error, isNull);
    expect(controller.selectedId, 'work-b');
    expect(body(tester).text, 'B 草稿');
    await switchWork(tester, '作品 A');
    expect(body(tester).text, 'A 后续草稿');
    expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
    expect(gateway.commands.length, 1);
  });

  testWidgets('刷新确认在途保存后原连接超时，保留 A 后续草稿并能继续保存 B', (tester) async {
    final delayed = Completer<LibraryResult>();
    final gateway = FakeLibraryGateway()..response = delayed;
    final controller = await mount(tester, gateway);
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 已提交正文',
    );
    await tester.pump();
    await tester.tap(find.text('保存正文').first);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'A 后续草稿',
    );
    controller.select('work-b');
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('body-chapter-1')),
      'B 待保存草稿',
    );
    await tester.tap(find.byTooltip('刷新作品'));
    await tester.pump();
    expect(
      controller
          .controllerFor('work-a')
          .workspace!
          .receipts
          .containsKey(gateway.commands.single.requestId),
      isTrue,
    );
    delayed.completeError(const GatewayFailure('迟到的连接超时', uncertain: true));
    await tester.pumpAndSettle();
    expect(controller.controllerFor('work-a').pending, isNull);
    expect(find.text('迟到的连接超时'), findsNothing);
    expect(find.text('重试上次操作'), findsNothing);
    expect(body(tester).text, 'B 待保存草稿');
    gateway.response = null;
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(gateway.workspace.work('work-b').chapters.first.body, 'B 待保存草稿');
    expect(gateway.commands.map((c) => c.target.workId), ['work-a', 'work-b']);
    await switchWork(tester, '作品 A');
    expect(body(tester).text, 'A 后续草稿');
    expect(find.text('有未保存草稿'), findsOneWidget);
    expect(find.text('服务端正文版本已变化，本地草稿已保留。'), findsNothing);
  });
}
