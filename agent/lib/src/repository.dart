import 'dart:convert';
import 'dart:io';

import 'package:novel_contracts/novel_contracts.dart';

abstract interface class WorkspaceRepository {
  Future<Workspace> load();
  Future<void> save(Workspace workspace, int expectedRevision);
}

class FileWorkspaceRepository implements WorkspaceRepository {
  FileWorkspaceRepository(this.file);
  final File file;
  static Future<FileWorkspaceRepository> open(String path) async {
    final repository = FileWorkspaceRepository(File(path));
    await repository.file.parent.create(recursive: true);
    if (!await repository.file.exists()) {
      await repository._write(demoWorkspace());
    }
    await repository.load();
    return repository;
  }

  @override
  Future<Workspace> load() async =>
      Workspace.fromJson(jsonDecode(await file.readAsString()));

  @override
  Future<void> save(Workspace workspace, int expectedRevision) async {
    if ((await load()).revision != expectedRevision) {
      throw const WorkspaceConflict();
    }
    await _write(workspace);
  }

  Future<void> _write(Workspace workspace) async {
    // A single service owns this repository. Rename commits one complete snapshot.
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode(workspace.toJson()),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class WorkspaceConflict implements Exception {
  const WorkspaceConflict();
}

class InMemoryWorkspaceRepository implements WorkspaceRepository {
  InMemoryWorkspaceRepository(this.workspace);
  Workspace workspace;
  @override
  Future<Workspace> load() async => workspace;
  @override
  Future<void> save(Workspace workspace, int expectedRevision) async {
    if (this.workspace.revision != expectedRevision) {
      throw const WorkspaceConflict();
    }
    this.workspace = workspace;
  }
}
