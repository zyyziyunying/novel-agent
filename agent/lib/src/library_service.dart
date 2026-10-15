import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'library_repository.dart';
import 'model.dart';
import 'knowledge_reader.dart';
import 'repository.dart';
import 'service.dart';

part 'library_discussion.dart';

const _bodyOperations = {
  'createChapter',
  'proposeChapter',
  'proposeEdit',
  'saveChapter',
  'restoreVersion',
  'acceptProposal',
  'rejectProposal',
  'rebuildMemory',
  'confirmReview',
};
const _modelOperations = {'proposeChapter', 'proposeEdit', 'rebuildMemory'};

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
  final Map<String, (String, Future<Json>)> _inFlight = {};
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _locked(_recoverDiscussions);

  Future<T> _locked<T>(Future<T> Function() work) {
    final future = _tail.then((_) => work());
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  Future<Json> snapshot() async {
    await initialize();
    return _locked(() async => _result(await repository.load()));
  }

  Json _result(LibraryWorkspace workspace, {bool reused = false}) => {
    'workspace': workspace.toJson(),
    'provider': model?.name,
    'modelAvailable': model != null,
    'reused': reused,
  };

  Future<Json> execute(LibraryCommand command) async {
    await initialize();
    return _execute(command);
  }

  Future<Json> _execute(LibraryCommand command) {
    final fingerprint = sha256
        .convert(utf8.encode(command.canonical))
        .toString();
    final pending = _inFlight[command.requestId];
    if (pending != null) {
      if (pending.$1 != fingerprint) {
        return Future.error(
          const LibraryFailure('request_conflict', '同一个请求编号不能用于不同操作。'),
        );
      }
      return pending.$2;
    }
    if (!_modelOperations.contains(command.operation) &&
        command.operation != 'sendDiscussionMessage') {
      return _locked(() async {
        final base = await repository.load();
        if (_check(base, command, fingerprint)) {
          return _result(base, reused: true);
        }
        final (works, libraries) = _bodyOperations.contains(command.operation)
            ? (await _applyBody(base, command), base.libraries)
            : command.operation == 'createDiscussion' ||
                  command.operation == 'adoptDiscussionMessage'
            ? _applyDiscussion(base, command)
            : _apply(base, command);
        return _commit(base, command, fingerprint, works, libraries);
      });
    }
    final future = command.operation == 'sendDiscussionMessage'
        ? _sendDiscussion(command, fingerprint)
        : _generate(command, fingerprint);
    _inFlight[command.requestId] = (fingerprint, future);
    unawaited(
      future.then<void>(
        (_) => _inFlight.remove(command.requestId),
        onError: (Object _) => _inFlight.remove(command.requestId),
      ),
    );
    return future;
  }

  bool _check(
    LibraryWorkspace base,
    LibraryCommand command,
    String fingerprint,
  ) {
    final receipt = base.receipts[command.requestId];
    if (receipt != null) {
      if (receipt.fingerprint != fingerprint) {
        throw const LibraryFailure('request_conflict', '同一个请求编号不能用于不同操作。');
      }
      return true;
    }
    if (base.revision != command.expectedRevision) {
      throw const LibraryFailure('version_conflict', '工作区已发生变化，请刷新后重新操作。');
    }
    try {
      base.validateTarget(command.target);
    } on FormatException {
      throw const LibraryFailure('target_missing', '请求指定的目标不存在。');
    }
    return false;
  }

  Future<Json> _generate(LibraryCommand command, String fingerprint) async {
    final base = await _locked(repository.load);
    if (_check(base, command, fingerprint)) return _result(base, reused: true);
    if (model == null) {
      throw const LibraryFailure('model_unavailable', '未配置模型，作品与资料读写仍可使用。');
    }
    final works = await _applyBody(base, command);
    return _locked(() async {
      final current = await repository.load();
      if (_check(current, command, fingerprint)) {
        return _result(current, reused: true);
      }
      return _commit(base, command, fingerprint, works, base.libraries);
    });
  }

  Future<List<NovelWork>> _applyBody(
    LibraryWorkspace base,
    LibraryCommand command,
  ) async {
    final owner = base.work(command.target.workId!);
    if (command.operation == 'acceptProposal') {
      final proposed = owner.proposals
          .where((p) => p.proposal.id == command.payload['proposalId'])
          .firstOrNull;
      if (proposed != null && !base.isBasisCurrent(proposed.basis)) {
        throw const LibraryFailure(
          'version_conflict',
          '提案所依据的正文或采用资料版本已改变，请重新生成。',
        );
      }
    }
    // Reuse the body transaction engine on one isolated domain view. Its
    // temporary receipt is discarded; only the format 2 commit below persists.
    final view = InMemoryWorkspaceRepository(base.workView(owner.id));
    final engine = NovelService(
      view,
      model,
      contextMetadata: {
        'workId': owner.id,
        'basis': base.captureBasis(owner.id).toJson(),
        'knowledgeDocuments': [
          for (final ref in owner.adoptedDocuments)
            {
              ...ref.toJson(),
              'libraryName': base.library(ref.libraryId).name,
              'version': base.documentVersion(ref).toJson(),
            },
        ],
      },
    );
    try {
      await engine.execute(
        NovelCommand(
          requestId: command.requestId,
          expectedRevision: base.revision,
          operation: command.operation,
          payload: command.payload,
        ),
      );
    } on NovelFailure catch (failure) {
      throw LibraryFailure(failure.code, failure.message);
    }
    final changed = await view.load();
    final replacement = NovelWork(
      id: owner.id,
      title: owner.title,
      knowledgeLinks: owner.knowledgeLinks,
      chapters: changed.chapters,
      memories: changed.memories,
      proposals: [
        for (final proposal in changed.proposals)
          WorkProposal(
            workId: owner.id,
            proposal: proposal,
            documents:
                owner.proposals
                    .where((p) => p.proposal.id == proposal.id)
                    .firstOrNull
                    ?.documents ??
                owner.adoptedDocuments,
            discussionSource: owner.proposals
                .where((p) => p.proposal.id == proposal.id)
                .firstOrNull
                ?.discussionSource,
          ),
      ],
      discussions: owner.discussions,
    );
    return [
      for (final work in base.works) work.id == owner.id ? replacement : work,
    ];
  }

  Future<Json> _commit(
    LibraryWorkspace base,
    LibraryCommand command,
    String fingerprint,
    List<NovelWork> works,
    List<KnowledgeLibrary> libraries,
  ) async {
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
  }

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
      case 'setKnowledgeLinks':
        final owner = base.work(command.target.workId!);
        final renamed = NovelWork(
          id: owner.id,
          title: command.operation == 'renameWork'
              ? payload['title']
              : owner.title,
          knowledgeLinks: command.operation == 'setKnowledgeLinks'
              ? (payload['links'] as List).map(LibraryLink.fromJson).toList()
              : owner.knowledgeLinks,
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
