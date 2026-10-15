import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/knowledge_metadata.dart';

void main() {
  testWidgets('同名目录条目可核对不同库、版本、简介和标签，包括未读全文的资料', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DocumentReference ref(String library, String version) => DocumentReference(
      libraryId: library,
      documentId: 'rules',
      versionId: version,
    );
    final read = ref('library-a', 'v1');
    final unread = ref('library-b', 'v3');
    KnowledgeVersion version(String id, String description, String tag) =>
        KnowledgeVersion(
          id: id,
          title: '行动规则',
          kind: 'setting',
          body: '不应在目录中显示的全文',
          description: description,
          tags: [tag],
          associatedWorkId: null,
          provenance: SourceProvenance(
            writer: SourceWriter(kind: 'author', id: 'author'),
            sources: [ExternalSource(kind: 'author', reference: '原始设定')],
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KnowledgeReadSummary(
              catalog: [
                knowledgeCatalogEntry(read, version('v1', '影子相关规则', '影子')),
                knowledgeCatalogEntry(unread, version('v3', '人物相关规则', '人物')),
              ],
              readDocuments: [read],
            ),
          ),
        ),
      ),
    );
    expect(find.text('行动规则 · 已加载全文'), findsOneWidget);
    expect(find.text('行动规则 · 仅看简介'), findsOneWidget);
    expect(
      find.text('知识库 ID：library-a · 资料 ID：rules · 版本 ID：v1'),
      findsOneWidget,
    );
    expect(
      find.text('知识库 ID：library-b · 资料 ID：rules · 版本 ID：v3'),
      findsOneWidget,
    );
    expect(find.text('简介：人物相关规则'), findsOneWidget);
    expect(find.text('标签：人物'), findsOneWidget);
    expect(find.text('不应在目录中显示的全文'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
