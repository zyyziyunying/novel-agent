import 'dart:convert';
import 'dart:io';

import 'package:novel_contracts/novel_contracts.dart';

abstract interface class LibraryRepository {
  Future<LibraryWorkspace> load();
  Future<void> save(LibraryWorkspace workspace, int expectedRevision);
}

class LibraryRepositoryConflict implements Exception {
  const LibraryRepositoryConflict();
}

LibraryWorkspace emptyLibraryWorkspace() =>
    LibraryWorkspace(revision: 0, works: [], libraries: [], receipts: {});

/// The entry point owns the data-directory lock; one service owns this store.
class FileLibraryRepository implements LibraryRepository {
  FileLibraryRepository(this.file);
  final File file;

  static Future<FileLibraryRepository> open(String path) async {
    final repository = FileLibraryRepository(File(path));
    await repository.file.parent.create(recursive: true);
    if (!await repository.file.exists()) {
      await repository._write(emptyLibraryWorkspace());
    }
    await repository.load(); // Never replace a malformed existing snapshot.
    return repository;
  }

  @override
  Future<LibraryWorkspace> load() async =>
      LibraryWorkspace.fromJson(jsonDecode(await file.readAsString()));

  @override
  Future<void> save(LibraryWorkspace workspace, int expectedRevision) async {
    if ((await load()).revision != expectedRevision) {
      throw const LibraryRepositoryConflict();
    }
    if (workspace.revision != expectedRevision + 1) {
      throw const FormatException('提交必须只递增一次修订号');
    }
    await _write(workspace);
  }

  Future<void> _write(LibraryWorkspace workspace) async {
    // Validate the complete snapshot before touching the temporary file.
    final encoded = jsonEncode(
      LibraryWorkspace.fromJson(workspace.toJson()).toJson(),
    );
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Cleanup cannot change whether rename committed the snapshot.
      }
    }
  }
}

class InMemoryLibraryRepository implements LibraryRepository {
  InMemoryLibraryRepository([LibraryWorkspace? workspace])
    : workspace = workspace ?? emptyLibraryWorkspace();
  LibraryWorkspace workspace;

  @override
  Future<LibraryWorkspace> load() async => workspace;

  @override
  Future<void> save(LibraryWorkspace workspace, int expectedRevision) async {
    if (this.workspace.revision != expectedRevision) {
      throw const LibraryRepositoryConflict();
    }
    if (workspace.revision != expectedRevision + 1) {
      throw const FormatException('提交必须只递增一次修订号');
    }
    this.workspace = LibraryWorkspace.fromJson(workspace.toJson());
  }
}
