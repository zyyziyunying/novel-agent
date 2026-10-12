import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'library_repository.dart';
import 'model.dart';

class LibraryFailure implements Exception {
  const LibraryFailure(this.code, this.message);
  final String code;
  final String message;
}

class LibraryService {
  LibraryService(this.repository, {this.model});
  final LibraryRepository repository;
  final NovelModel? model;
  Future<void> _tail = Future.value();

  Future<T> _locked<T>(Future<T> Function() work) {
    final future = _tail.then((_) => work());
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  Future<Json> snapshot() =>
      _locked(() async => _result(await repository.load()));

  Json _result(LibraryWorkspace workspace, {bool reused = false}) => {
    'workspace': workspace.toJson(),
    'provider': model?.name,
    'modelAvailable': model != null,
    'reused': reused,
  };

  // M2 has no model calls: hold one queue through read, receipt check and commit.
  // A concurrent duplicate reaches its receipt after the first commit.
  Future<Json> execute(LibraryCommand command) => _locked(() async {
    final base = await repository.load();
    final fingerprint = sha256
        .convert(utf8.encode(command.canonical))
        .toString();
    final receipt = base.receipts[command.requestId];
    if (receipt != null) {
      if (receipt.fingerprint != fingerprint) {
        throw const LibraryFailure('request_conflict', '同一个请求编号不能用于不同操作。');
      }
      return _result(base, reused: true);
    }
    if (base.revision != command.expectedRevision) {
      throw const LibraryFailure('version_conflict', '工作区已发生变化，请刷新后重新操作。');
    }
    try {
      base.validateTarget(command.target);
    } on FormatException {
      throw const LibraryFailure('target_missing', '请求指定的目标不存在。');
    }

    final (works, libraries) = _apply(base, command);
    LibraryWorkspace next;
    try {
      next = LibraryWorkspace(
        revision: base.revision + 1,
        works: works,
        libraries: libraries,
        receipts: {
          ...base.receipts,
          command.requestId: BoundReceipt(
            fingerprint: fingerprint,
            revision: base.revision + 1,
            target: command.target,
          ),
        },
      );
    } on FormatException {
      throw const LibraryFailure('invalid_reference', '资料包含不存在的来源或关联。');
    }
    try {
      await repository.save(next, base.revision);
    } on LibraryRepositoryConflict {
      throw const LibraryFailure('version_conflict', '工作区已发生变化，操作未应用。');
    }
    return _result(next);
  });

  (List<NovelWork>, List<KnowledgeLibrary>) _apply(
    LibraryWorkspace base,
    LibraryCommand command,
  ) {
    final payload = command.payload;
    var works = base.works;
    var libraries = base.libraries;
    switch (command.operation) {
      case 'createWork':
        final id = payload['id'] as String;
        if (works.any((w) => w.id == id)) {
          throw const LibraryFailure('target_exists', '作品编号已存在。');
        }
        works = [
          ...works,
          NovelWork(
            id: id,
            title: payload['title'],
            knowledgeLinks: [],
            chapters: [],
            proposals: [],
            memories: [],
            discussions: [],
          ),
        ];
      case 'renameWork':
        final owner = base.work(command.target.workId!);
        final renamed = NovelWork(
          id: owner.id,
          title: payload['title'],
          knowledgeLinks: owner.knowledgeLinks,
          chapters: owner.chapters,
          proposals: owner.proposals,
          memories: owner.memories,
          discussions: owner.discussions,
        );
        works = [
          for (final work in works) work.id == owner.id ? renamed : work,
        ];
      case 'createLibrary':
        final id = payload['id'] as String;
        if (libraries.any((l) => l.id == id)) {
          throw const LibraryFailure('target_exists', '知识库编号已存在。');
        }
        libraries = [
          ...libraries,
          KnowledgeLibrary(id: id, name: payload['name'], documents: []),
        ];
      case 'renameLibrary':
      case 'saveDocument':
        final owner = base.library(command.target.libraryId!);
        final replacement = KnowledgeLibrary(
          id: owner.id,
          name: command.operation == 'renameLibrary'
              ? payload['name']
              : owner.name,
          documents: command.operation == 'saveDocument'
              ? _saveDocument(owner, payload)
              : owner.documents,
        );
        libraries = [
          for (final library in libraries)
            library.id == owner.id ? replacement : library,
        ];
      case 'proposeChapter':
      case 'proposeEdit':
      case 'rebuildMemory':
      case 'sendDiscussionMessage':
        if (model == null) {
          throw const LibraryFailure('model_unavailable', '未配置模型，资料读写仍可使用。');
        }
        throw const LibraryFailure(
          'operation_unavailable',
          '该模型操作尚未接入格式 2 服务。',
        );
      default:
        throw const LibraryFailure('operation_unavailable', '该操作将在后续里程碑接入。');
    }
    return (works, libraries);
  }

  List<KnowledgeDocument> _saveDocument(
    KnowledgeLibrary library,
    Json payload,
  ) {
    final id = payload['documentId'] as String;
    final previous = payload['expectedVersionId'] as String?;
    final version = KnowledgeVersion.fromJson(payload['version']);
    final existing = library.documents.where((d) => d.id == id).firstOrNull;
    if (existing == null ? previous != null : previous != existing.head) {
      throw const LibraryFailure('version_conflict', '资料版本已改变，请刷新后重新操作。');
    }
    if (existing?.versions.any((v) => v.id == version.id) ?? false) {
      throw const LibraryFailure('version_conflict', '新资料版本编号已使用。');
    }
    final replacement = KnowledgeDocument(
      id: id,
      head: version.id,
      versions: [...?existing?.versions, version],
    );
    return [
      for (final document in library.documents)
        if (document.id != id) document else replacement,
      if (existing == null) replacement,
    ];
  }
}
