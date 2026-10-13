import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_controller.dart';
import 'package:novel_workbench/src/library_gateway.dart';

import 'support/library_gateway.dart';

void main() {
  test('目录操作迟到失败仍归属发起作品，刷新错误保持全局可见', () async {
    final gateway = DelayedCatalogGateway();
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final renaming = controller.renameWork('work-a', 'A 新名称');
    controller.select('work-b');
    gateway.release.completeError(const GatewayFailure('A 命名冲突'));
    expect(await renaming, isFalse);
    expect(controller.errorWorkId, 'work-a');
    expect(controller.error, 'A 命名冲突');
    expect(controller.selectedId, 'work-b');
    expect(controller.workspace!.work('work-b').title, '作品 B');

    gateway.failLoad = true;
    expect(await controller.load(), isFalse);
    expect(controller.errorWorkId, isNull);
    expect(controller.error, '会话令牌不正确');
  });

  test('切换作品后重试原目录请求，失败归属不随当前选择变化', () async {
    final gateway = DelayedCatalogGateway();
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final renaming = controller.renameWork('work-a', 'A 新名称');
    gateway.release.completeError(
      const GatewayFailure('结果未知', uncertain: true),
    );
    expect(await renaming, isFalse);
    final original = controller.pending!;
    controller.select('work-b');
    gateway.release = Completer<LibraryResult>();
    final retrying = controller.retry();
    gateway.release.completeError(const GatewayFailure('A 原请求冲突'));
    expect(await retrying, isFalse);
    expect(gateway.commands.last.toJson(), original.toJson());
    expect(controller.errorWorkId, 'work-a');
    expect(controller.pending, isNull);
    expect(controller.selectedId, 'work-b');
    expect(await controller.load(), isTrue);
    expect(controller.error, isNull);
    expect(controller.errorWorkId, isNull);
  });

  test('更新连接保留未确认的原请求，并使用新会话重试', () async {
    final original = FakeLibraryGateway()
      ..failure = const GatewayFailure('结果未知', uncertain: true);
    final controller = LibraryController(original);
    addTearDown(controller.dispose);
    await controller.load();
    final work = controller.controllerFor('work-a');
    await work.act('saveChapter', {'chapterId': 'chapter-1', 'body': '待确认正文'});
    final pending = work.pending!;
    final renewed = FakeLibraryGateway()..workspace = original.workspace;
    expect(await controller.reconnect(renewed), isTrue);
    expect(controller.controllerFor('work-a'), same(work));
    expect(work.pending, same(pending));
    expect(await work.retry(), isTrue);
    expect(renewed.commands.single.toJson(), original.commands.single.toJson());
    expect(work.pending, isNull);
    expect(work.workspace!.chapters.first.body, '待确认正文');
  });

  test('更新会话读到已提交回执后解除未知状态，不重复保存', () async {
    final original = FakeLibraryGateway()
      ..commitBeforeFailure = true
      ..failure = const GatewayFailure('响应丢失', uncertain: true);
    final controller = LibraryController(original);
    addTearDown(controller.dispose);
    await controller.load();
    final work = controller.controllerFor('work-a');
    await work.act('saveChapter', {'chapterId': 'chapter-1', 'body': '已提交正文'});
    expect(work.pending, isNotNull);
    final renewed = FakeLibraryGateway()..workspace = original.workspace;
    expect(await controller.reconnect(renewed), isTrue);
    expect(work.pending, isNull);
    expect(work.chapterSave('chapter-1')!.body, '已提交正文');
    expect(renewed.commands, isEmpty);
  });

  test('在途保存期间不能更换会话，较旧快照也不能替换当前连接', () async {
    final original = FakeLibraryGateway()
      ..response = Completer<LibraryResult>();
    final controller = LibraryController(original);
    addTearDown(controller.dispose);
    await controller.load();
    final stale = FakeLibraryGateway();
    final saving = controller.controllerFor('work-a').act('saveChapter', {
      'chapterId': 'chapter-1',
      'body': '新版本',
    });
    expect(controller.canReconnect, isFalse);
    expect(await controller.reconnect(stale), isFalse);
    expect(controller.gateway, same(original));
    original.response!.complete(original.result());
    await saving;
    expect(controller.canReconnect, isTrue);
    expect(await controller.reconnect(FakeLibraryGateway()), isFalse);
    expect(controller.gateway, same(original));
    expect(controller.workspace!.revision, 1);
  });

  test('中央刷新已确认 A 回执后，迟到网络失败仍视为成功并允许 B 写入', () async {
    final delayed = Completer<LibraryResult>();
    final gateway = FakeLibraryGateway()..response = delayed;
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final a = controller.controllerFor('work-a');
    final saving = a.act('saveChapter', {
      'chapterId': 'chapter-1',
      'body': 'A 已提交正文',
    });
    final original = gateway.commands.single;
    controller.select('work-b');
    expect(await controller.load(), isTrue);
    expect(a.workspace!.receipts.containsKey(original.requestId), isTrue);
    delayed.completeError(const GatewayFailure('迟到的连接超时', uncertain: true));
    expect(await saving, isTrue);
    expect(a.pending, isNull);
    expect(a.error, isNull);
    expect(a.lastConfirmedCommand!.requestId, original.requestId);
    expect(a.chapterSave('chapter-1')!.body, 'A 已提交正文');
    expect(controller.canChangeCatalog, isTrue);
    expect(controller.selectedId, 'work-b');
    gateway.response = null;
    expect(
      await controller.controllerFor('work-b').act('saveChapter', {
        'chapterId': 'chapter-1',
        'body': 'B 新版正文',
      }),
      isTrue,
    );
    expect(gateway.commands.map((c) => c.target.workId), ['work-a', 'work-b']);
    expect(gateway.workspace.work('work-a').chapters.first.versions.length, 2);
  });

  test('仅有其他作品回执不能确认 A 的未知请求，仍保留原请求和写入阻断', () async {
    final gateway = FakeLibraryGateway()
      ..failure = const GatewayFailure('结果未知', uncertain: true);
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final a = controller.controllerFor('work-a');
    expect(
      await a.act('saveChapter', {'chapterId': 'chapter-1', 'body': 'A 未确认正文'}),
      isFalse,
    );
    final original = a.pending;
    gateway.failure = null;
    // A separate client can commit B while the page still waits for A.
    await gateway.execute(
      LibraryCommand(
        requestId: 'external-b',
        expectedRevision: 0,
        target: CommandTarget.work('work-b'),
        operation: 'renameWork',
        payload: {'title': 'B 外部命名'},
      ),
    );
    expect(await controller.load(), isTrue);
    expect(controller.workspace!.receipts.containsKey('external-b'), isTrue);
    expect(a.pending, same(original));
    expect(a.lastConfirmedCommand, isNull);
    expect(controller.canChangeCatalog, isFalse);
    expect(
      await controller.controllerFor('work-b').act('saveChapter', {
        'chapterId': 'chapter-1',
        'body': 'B 草稿',
      }),
      isFalse,
    );
    expect(gateway.commands.length, 2);
  });

  test('A 的旧响应不会回退刷新及 B 保存后的目录，当前选择仍是 B', () async {
    final delayed = Completer<LibraryResult>();
    final gateway = FakeLibraryGateway()..response = delayed;
    final controller = LibraryController(gateway);
    addTearDown(controller.dispose);
    await controller.load();
    final saving = controller.controllerFor('work-a').act('saveChapter', {
      'chapterId': 'chapter-1',
      'body': 'A 已提交正文',
    });
    final oldResult = gateway.result();
    controller.select('work-b');
    await controller.load();
    gateway.response = null;
    expect(
      await controller.controllerFor('work-b').act('saveChapter', {
        'chapterId': 'chapter-1',
        'body': 'B 新版正文',
      }),
      isTrue,
    );
    delayed.complete(oldResult);
    expect(await saving, isTrue);
    expect(controller.workspace!.revision, 2);
    expect(controller.selectedId, 'work-b');
    expect(
      controller.controllerFor('work-b').workspace!.chapters.first.body,
      'B 新版正文',
    );
    expect(
      controller.controllerFor('work-a').workspace!.chapters.first.body,
      'A 已提交正文',
    );
    expect(gateway.commands.map((c) => c.target.workId), ['work-a', 'work-b']);
    expect(gateway.commands.map((c) => c.requestId).toSet().length, 2);
  });
}

class DelayedCatalogGateway extends FakeLibraryGateway {
  Completer<LibraryResult> release = Completer<LibraryResult>();
  bool failLoad = false;
  @override
  Future<LibraryResult> load() async {
    if (failLoad) throw const GatewayFailure('会话令牌不正确');
    return result();
  }

  @override
  Future<LibraryResult> execute(LibraryCommand command) {
    commands.add(command);
    return release.future;
  }
}
