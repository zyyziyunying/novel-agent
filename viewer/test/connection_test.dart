import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_gateway.dart';
import 'package:novel_workbench/src/workbench.dart';

import 'support/library_gateway.dart';

class ConnectionGateway extends FakeLibraryGateway {
  bool closed = false;
  bool authenticated = true;
  @override
  Future<LibraryResult> load() async {
    if (!authenticated) throw const GatewayFailure('会话令牌不正确');
    return super.load();
  }

  @override
  void close() => closed = true;
}

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);
  Future<void> mount(
    WidgetTester tester,
    LibraryGateway Function(Uri, String) factory,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NovelApp(gatewayFactory: factory));
    await tester.pumpAndSettle();
  }

  testWidgets('错误令牌留在连接表单，纠正后可直接进入工作台', (tester) async {
    final failed = ConnectionGateway()..authenticated = false;
    final valid = ConnectionGateway();
    await mount(tester, (_, token) => token == 'correct' ? valid : failed);
    await tester.enterText(field('工作台会话令牌'), 'wrong');
    await tester.tap(find.text('连接工作台'));
    await tester.pumpAndSettle();
    expect(find.text('会话令牌不正确'), findsOneWidget);
    expect(field('工作台会话令牌'), findsOneWidget);
    expect(failed.closed, isTrue);
    await tester.enterText(field('工作台会话令牌'), 'correct');
    await tester.tap(find.text('连接工作台'));
    await tester.pumpAndSettle();
    expect(find.text('作品 A'), findsOneWidget);
    expect(field('工作台会话令牌'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('更新令牌失败不丢正文草稿，成功后仍可保存到原作品', (tester) async {
    final original = ConnectionGateway();
    final failed = ConnectionGateway()..authenticated = false;
    final renewed = ConnectionGateway()..workspace = original.workspace;
    await mount(
      tester,
      (_, token) => switch (token) {
        'original' => original,
        'renewed' => renewed,
        _ => failed,
      },
    );
    await tester.enterText(field('工作台会话令牌'), 'original');
    await tester.tap(find.text('连接工作台'));
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('body-chapter-1'));
    await tester.enterText(body, '更新令牌期间必须保留的正文草稿');
    await tester.tap(find.byTooltip('连接设置'));
    await tester.pumpAndSettle();
    await tester.enterText(field('工作台会话令牌'), 'wrong');
    await tester.tap(find.text('更新连接'));
    await tester.pumpAndSettle();
    expect(find.text('会话令牌不正确').last, findsOneWidget);
    expect(original.closed, isFalse);
    await tester.enterText(field('工作台会话令牌'), 'renewed');
    await tester.tap(find.text('更新连接'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(body).controller!.text, '更新令牌期间必须保留的正文草稿');
    expect(original.closed, isTrue);
    expect(failed.closed, isTrue);
    await tester.tap(find.text('保存正文').first);
    await tester.pumpAndSettle();
    expect(
      renewed.workspace.work('work-a').chapters.first.body,
      '更新令牌期间必须保留的正文草稿',
    );
    expect(original.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('资料编辑失败可在原弹窗更新令牌，继续编辑并保存原草稿', (tester) async {
    final original = ConnectionGateway();
    original.workspace = LibraryWorkspace(
      revision: 0,
      works: original.workspace.works,
      libraries: [
        KnowledgeLibrary(
          id: 'library',
          name: '资料库',
          documents: [
            KnowledgeDocument(
              id: 'document',
              head: 'version',
              versions: [
                KnowledgeVersion(
                  id: 'version',
                  title: '人物设定',
                  kind: 'setting',
                  body: '原设定',
                  provenance: SourceProvenance(
                    writer: SourceWriter(kind: 'author', id: 'local-author'),
                    sources: [
                      ExternalSource(kind: 'author', reference: '作者笔记'),
                    ],
                  ),
                  associatedWorkId: null,
                ),
              ],
            ),
          ],
        ),
      ],
      receipts: {},
    );
    final renewed = ConnectionGateway()..workspace = original.workspace;
    await mount(tester, (_, token) => token == 'renewed' ? renewed : original);
    await tester.enterText(field('工作台会话令牌'), 'original');
    await tester.tap(find.text('连接工作台'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理知识库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    await tester.enterText(field('资料正文'), '重连前的资料草稿');
    original.failure = const GatewayFailure('会话令牌不正确');
    await tester.tap(find.text('保存资料版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '连接设置'));
    await tester.pumpAndSettle();
    await tester.enterText(field('工作台会话令牌'), 'renewed');
    await tester.tap(find.text('更新连接'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(field('资料正文')).controller!.text,
      '重连前的资料草稿',
    );
    expect(tester.widget<TextField>(field('资料正文')).readOnly, isFalse);
    await tester.enterText(field('资料正文'), '重连后继续完善的资料草稿');
    await tester.tap(find.text('保存资料版本'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      renewed.workspace.library('library').documents.single.current.body,
      '重连后继续完善的资料草稿',
    );
    expect(
      original.workspace.library('library').documents.single.current.body,
      '原设定',
    );
    expect(tester.takeException(), isNull);
  });
}
