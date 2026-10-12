import 'dart:io';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';
import 'support/library_server.dart';

void main() {
  test(
    '无模型 HTTP 保存独立库、多作品引用和历史采用，强制重启后复用回执和旧版本',
    () async {
      final directory = await Directory.systemTemp.createTemp('novel-m4-http-');
      addTearDown(() => directory.delete(recursive: true));
      var server = await LibraryAgentProcess.start(directory);
      addTearDown(() => server.stop());
      var revision = 0;
      Future<Json> execute(LibraryCommand c) async {
        final result = await server.execute(c);
        revision = result['workspace']['revision'];
        return result;
      }

      for (final id in ['work-a', 'work-b', 'work-c']) {
        await execute(createWork(revision, id));
      }
      for (final id in ['library-a', 'library-b']) {
        await execute(createLibrary(revision, id));
        await execute(
          saveDocument(
            revision,
            requestId: 'document-$id',
            libraryId: id,
            workId: null,
          ),
        );
      }
      LibraryCommand adopt(
        String workId,
        List<String> libraries,
        String version,
      ) => command(
        'adopt-$workId-$version',
        revision,
        'setKnowledgeLinks',
        {
          'links': [
            for (final id in libraries)
              LibraryLink(libraryId: id, versions: {'doc-a': version}).toJson(),
          ],
        },
        target: CommandTarget.work(workId),
      );
      await execute(adopt('work-a', ['library-a', 'library-b'], 'v1'));
      await execute(adopt('work-b', ['library-a'], 'v1'));
      final published = saveDocument(
        revision,
        requestId: 'publish-v2',
        versionId: 'v2',
        previous: 'v1',
        workId: null,
        body: '新版资料',
      );
      await execute(published);
      // A intentionally adopts only K1 v2; K2 and B keep v1.
      final adopted = command(
        'adopt-a-v2',
        revision,
        'setKnowledgeLinks',
        {
          'links': [
            LibraryLink(
              libraryId: 'library-a',
              versions: {'doc-a': 'v2'},
            ).toJson(),
            LibraryLink(
              libraryId: 'library-b',
              versions: {'doc-a': 'v1'},
            ).toJson(),
          ],
        },
        target: CommandTarget.work('work-a'),
      );
      final before = LibraryWorkspace.fromJson(
        (await execute(adopted))['workspace'],
      );
      final stale = saveDocument(
        revision,
        requestId: 'stale-update',
        versionId: 'v3',
        previous: 'v1',
        workId: null,
        body: '不能覆盖',
      );
      final conflict = await server.request(
        '/libraryAction',
        body: {'data': stale.toJson()},
      );
      expect(conflict.$1, 409);
      expect(conflict.$2['status'], 'ABORTED');
      expect(conflict.$2['message'], contains('资料版本已改变'));
      await server.stop(abrupt: true);
      server = await LibraryAgentProcess.start(directory);
      final state = (await server.request('/libraryWorkspace')).$2;
      final after = LibraryWorkspace.fromJson(state['workspace']);
      expect(state['modelAvailable'], isFalse);
      expect(after.toJson(), before.toJson());
      expect(after.work('work-a').adoptedDocuments.map((r) => r.versionId), [
        'v2',
        'v1',
      ]);
      expect(after.work('work-b').adoptedDocuments.single.versionId, 'v1');
      expect(after.work('work-c').knowledgeLinks, isEmpty);
      expect(after.workView('work-c').documents, isEmpty);
      expect(
        after.workView('work-b').documents.single.body,
        contains('正文保持原样'),
      );
      expect(
        after.library('library-a').documents.single.versions.map((v) => v.id),
        ['v1', 'v2'],
      );
      expect(
        after
            .library('library-a')
            .documents
            .single
            .current
            .provenance
            .writer
            .id,
        'Codex',
      );
      expect((await server.execute(published))['reused'], isTrue);
      expect((await server.execute(adopted))['reused'], isTrue);
      expect(
        (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
        before.revision,
      );
      expect(
        after.works.every((w) => w.chapters.isEmpty && w.memories.isEmpty),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
