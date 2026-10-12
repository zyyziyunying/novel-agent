import 'dart:convert';
import 'dart:io';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('library-repository-');
    path = '${directory.path}/library-workspace.json';
  });
  tearDown(() => directory.delete(recursive: true));

  test('首次初始化空格式 2，不读取或修改旧文件', () async {
    final old = File('${directory.path}/workspace.json');
    await old.writeAsString('旧快照即使损坏也不读取');
    final repository = await FileLibraryRepository.open(path);
    expect((await repository.load()).toJson(), {
      'schemaVersion': 2,
      'revision': 0,
      'works': [],
      'libraries': [],
      'receipts': {},
    });
    expect(await old.readAsString(), '旧快照即使损坏也不读取');
  });

  test('完整内容、资料历史和请求回执冷启动后恢复并去重', () async {
    final repository = await FileLibraryRepository.open(path);
    final service = LibraryService(repository);
    await service.execute(createWork());
    await service.execute(createLibrary());
    final original = saveDocument(2);
    await service.execute(original);
    await service.execute(
      saveDocument(
        3,
        requestId: 'save-v2',
        versionId: 'v2',
        previous: 'v1',
        body: '  第二版本\n',
      ),
    );
    final before = (await repository.load()).toJson();
    final reopened = await FileLibraryRepository.open(path);
    expect((await reopened.load()).toJson(), before);
    final replay = await LibraryService(reopened).execute(original);
    expect(replay['reused'], isTrue);
    expect(replay['workspace'], before);
    expect(
      (await reopened.load()).libraries.single.documents.single.versions.length,
      2,
    );
  });

  for (final invalid in [
    '{',
    jsonEncode(demoWorkspace().toJson()),
    jsonEncode({...emptyLibraryWorkspace().toJson(), 'schemaVersion': 99}),
    jsonEncode({...emptyLibraryWorkspace().toJson(), 'revision': 1.0}),
    jsonEncode({...emptyLibraryWorkspace().toJson(), 'unknown': true}),
  ]) {
    test('损坏、旧格式、未知版本或非法字段拒绝加载且不覆盖: $invalid', () async {
      await File(path).writeAsString(invalid);
      await expectLater(
        FileLibraryRepository.open(path),
        throwsFormatException,
      );
      expect(await File(path).readAsString(), invalid);
    });
  }

  test('未提交临时快照不被加载；新提交覆盖临时文件', () async {
    final repository = await FileLibraryRepository.open(path);
    final temporary = File('$path.tmp');
    await temporary.writeAsString('{"revision":999,"partial":');
    final reopened = await FileLibraryRepository.open(path);
    expect((await reopened.load()).revision, 0);
    await LibraryService(reopened).execute(createWork());
    expect((await repository.load()).revision, 1);
    expect(await temporary.exists(), isFalse);
  });

  test('临时写入失败不产生半份资料或回执；修复后同请求可提交', () async {
    final repository = await FileLibraryRepository.open(path);
    final service = LibraryService(repository);
    await service.execute(createWork());
    await service.execute(createLibrary());
    final before = await File(path).readAsString();
    final blocked = await Directory('$path.tmp').create();
    final original = saveDocument(2);
    await expectLater(
      service.execute(original),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path).readAsString(), before);
    final reopened = await FileLibraryRepository.open(path);
    expect((await reopened.load()).libraries.single.documents, isEmpty);
    expect(
      (await reopened.load()).receipts.containsKey(original.requestId),
      isFalse,
    );
    await blocked.delete();
    await service.execute(original);
    expect((await repository.load()).revision, 3);
    expect(
      (await LibraryService(reopened).execute(original))['reused'],
      isTrue,
    );
  });

  test('仓库拒绝旧修订与多次递增，不替换已提交快照', () async {
    final repository = await FileLibraryRepository.open(path);
    await LibraryService(repository).execute(createWork());
    final before = await File(path).readAsString();
    final current = await repository.load();
    await expectLater(
      repository.save(current, 0),
      throwsA(isA<LibraryRepositoryConflict>()),
    );
    await expectLater(repository.save(current, 1), throwsFormatException);
    expect(await File(path).readAsString(), before);
  });

  test('重命名与更新仅改明确目标，历史采用引用在冷启动后保留', () async {
    final repository = await FileLibraryRepository.open(path);
    final service = LibraryService(repository);
    await service.execute(createWork());
    await service.execute(createLibrary());
    await service.execute(saveDocument(2));
    final saved = await repository.load();
    final json = saved.toJson();
    json['revision'] = 4;
    json['works'][0]['knowledgeLinks'] = [
      {
        'libraryId': 'library-a',
        'versions': {'doc-a': 'v1'},
      },
    ];
    // M4 adoption is not implemented here; an M1-valid saved fixture proves preservation.
    await repository.save(LibraryWorkspace.fromJson(json), 3);
    await service.execute(
      saveDocument(4, requestId: 'save-v2', versionId: 'v2', previous: 'v1'),
    );
    final reopened = await FileLibraryRepository.open(path);
    final current = await reopened.load();
    expect(current.libraries.single.documents.single.head, 'v2');
    expect(current.works.single.adoptedDocuments.single.versionId, 'v1');
    expect(
      current
          .documentVersion(current.works.single.adoptedDocuments.single)
          .toJson(),
      saveDocument(2).payload['version'],
    );
  });
}
