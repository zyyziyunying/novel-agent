import 'package:flutter/foundation.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'controller.dart';
import 'gateway.dart';
import 'library_gateway.dart';

part 'discussion_controller.dart';

/// Owns the catalog; each work owns a separate editor and request controller.
class LibraryController extends ChangeNotifier {
  LibraryController(LibraryGateway gateway) : _gateway = gateway;
  LibraryGateway _gateway;
  LibraryGateway get gateway => _gateway;
  bool _reconnecting = false;
  LibraryWorkspace? workspace;
  String? selectedId;
  String? selectedLibraryId;
  bool showingKnowledge = false;
  bool showingDiscussion = false;
  final Map<String, String> selectedDiscussions = {};
  final Map<(String, String), DiscussionRequestState> discussionRequests = {};
  String? provider;
  bool modelAvailable = false;
  bool busy = false;
  String? error;
  String? _errorWorkId;
  String? get errorWorkId => error == null ? null : _errorWorkId;
  String? errorForWork(String? workId) =>
      errorWorkId == null || errorWorkId == workId ? error : null;
  LibraryCommand? pending;
  final Map<String, WorkspaceController> _controllers = {};
  final String _session = 'catalog-${DateTime.now().microsecondsSinceEpoch}';
  int _sequence = 0;
  bool _disposed = false;
  Iterable<WorkspaceController> get workControllers => _controllers.values;
  WorkspaceController controllerFor(String id) => _controllers[id]!;
  bool get hasPending =>
      pending != null ||
      _controllers.values.any((c) => c.pending != null) ||
      discussionRequests.values.any((s) => s.pending != null);
  bool get canChangeCatalog => !busy && !hasPending;
  bool get canReconnect =>
      !_disposed &&
      !busy &&
      !_controllers.values.any((c) => c.busy) &&
      !discussionRequests.values.any((s) => s.busy);
  String newWorkId() => 'work-$_session-${++_sequence}';
  String newKnowledgeId(String kind) => '$kind-$_session-${++_sequence}';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void showKnowledge(bool show) {
    if (show && !showingKnowledge) _preferLinkedLibrary();
    showingKnowledge = show;
    showingDiscussion = false;
    notifyListeners();
  }

  void showDiscussion(bool show) {
    showingDiscussion = show;
    showingKnowledge = false;
    notifyListeners();
  }

  void selectLibrary(String id) {
    if (workspace!.libraries.any((l) => l.id == id)) {
      selectedLibraryId = id;
      notifyListeners();
    }
  }

  void select(String id) {
    if (workspace!.works.any((w) => w.id == id)) {
      final changed = selectedId != id;
      selectedId = id;
      if (changed) _preferLinkedLibrary();
      notifyListeners();
    }
  }

  void _preferLinkedLibrary() {
    final links = workspace?.works
        .where((work) => work.id == selectedId)
        .firstOrNull
        ?.knowledgeLinks;
    if (links != null &&
        links.isNotEmpty &&
        !links.any((link) => link.libraryId == selectedLibraryId)) {
      selectedLibraryId = links.first.libraryId;
    }
    selectedLibraryId ??= workspace?.libraries.firstOrNull?.id;
  }

  Future<bool> load() => _run(() async {
    _apply(await gateway.load());
    if (pending != null &&
        workspace!.receipts.containsKey(pending!.requestId)) {
      pending = null;
    }
  });

  /// Verify the new session before replacing transport. Editor state and
  /// uncertain requests stay on this controller and can reuse saved receipts.
  Future<bool> reconnect(LibraryGateway candidate) async {
    if (!canReconnect) {
      candidate.close();
      return false;
    }
    var installed = false;
    _reconnecting = true;
    try {
      await _run(() async {
        final result = await candidate.load();
        if (_disposed) return;
        if (workspace != null &&
            result.workspace.revision < workspace!.revision) {
          throw const GatewayFailure('Agent 数据早于当前工作台，连接未更换。');
        }
        final previous = _gateway;
        _gateway = candidate;
        installed = true;
        _apply(result);
        if (pending != null &&
            workspace!.receipts.containsKey(pending!.requestId)) {
          pending = null;
        }
        previous.close();
      });
      return installed;
    } finally {
      _reconnecting = false;
      if (!installed) candidate.close();
    }
  }

  Future<bool> createWork(String id, String title) => _catalog(
    'createWork',
    CommandTarget.catalog(),
    {'id': id, 'title': title},
  );
  Future<bool> renameWork(String id, String title) =>
      _catalog('renameWork', CommandTarget.work(id), {'title': title});
  Future<bool> createLibrary(String id, String name) => _catalog(
    'createLibrary',
    CommandTarget.catalog(),
    {'id': id, 'name': name},
  );
  Future<bool> renameLibrary(String id, String name) =>
      _catalog('renameLibrary', CommandTarget.library(id), {'name': name});
  Future<bool> setKnowledgeLinks(String workId, List<LibraryLink> links) =>
      _catalog('setKnowledgeLinks', CommandTarget.work(workId), {
        'links': links.map((l) => l.toJson()).toList(),
      });
  Future<bool> saveKnowledgeDocument({
    required String libraryId,
    required String documentId,
    required String? expectedVersionId,
    required KnowledgeVersion version,
  }) => _catalog(
    'saveDocument',
    CommandTarget.library(libraryId, workId: version.associatedWorkId),
    {
      'documentId': documentId,
      'expectedVersionId': expectedVersionId,
      'version': version.toJson(),
    },
  );
  Future<bool> _catalog(
    String operation,
    CommandTarget target,
    Json payload,
  ) async {
    if (!canChangeCatalog || workspace == null) return false;
    return _run(() async {
      await _submit(
        LibraryCommand(
          requestId: '$_session-${++_sequence}',
          expectedRevision: workspace!.revision,
          target: target,
          operation: operation,
          payload: payload,
        ),
      );
    }, workId: target.workId);
  }

  Future<bool> retry() async {
    if (busy || pending == null) return false;
    return _run(() => _submit(pending!), workId: pending!.target.workId);
  }

  Future<void> _submit(LibraryCommand command) async {
    try {
      _apply(await gateway.execute(command));
      pending = null;
    } on GatewayFailure catch (failure) {
      if (workspace?.receipts.containsKey(command.requestId) ?? false) {
        pending = null;
        return;
      }
      pending = failure.uncertain ? command : null;
      rethrow;
    }
  }

  Future<bool> _run(Future<void> Function() work, {String? workId}) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    _errorWorkId = workId;
    notifyListeners();
    try {
      await work();
      return true;
    } on GatewayFailure catch (failure) {
      error = failure.message;
    } on FormatException {
      error = '请输入有效的名称、正文和来源。';
    } on Object {
      error = '无法完成操作，请刷新检查当前状态。';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
    return false;
  }

  void _apply(LibraryResult result) {
    if (_disposed ||
        (workspace != null &&
            result.workspace.revision < workspace!.revision)) {
      return;
    }
    workspace = result.workspace;
    provider = result.provider;
    modelAvailable = result.modelAvailable;
    for (final state in discussionRequests.values) {
      final turn = state.pending == null
          ? null
          : _discussionTurn(state.pending!);
      if (turn != null && turn.status != 'pending') {
        state.pending = null;
        state.error = turn.status == 'completed'
            ? null
            : discussionFailure(turn.errorCode);
      }
    }
    for (final work in workspace!.works) {
      if (!_controllers.containsKey(work.id)) {
        final controller = WorkspaceController(
          _WorkGateway(this, work.id),
          requestNamespace: work.id,
        );
        _controllers[work.id] = controller;
        controller.addListener(_workChanged);
      }
      _controllers[work.id]!.update(
        WorkspaceResult(workspace!.workView(work.id), provider ?? '未配置模型'),
      );
    }
    selectedId ??= workspace!.works.firstOrNull?.id;
    if (selectedLibraryId == null) _preferLinkedLibrary();
    notifyListeners();
  }

  void _workChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.removeListener(_workChanged);
      controller.dispose();
    }
    gateway.close();
    super.dispose();
  }
}

/// The work ID is captured when this gateway is created. UI selection never
/// participates in request construction, retry, response or receipt handling.
class _WorkGateway implements NovelGateway {
  _WorkGateway(this.catalog, this.workId);
  final LibraryController catalog;
  final String workId;
  WorkspaceResult _view() => WorkspaceResult(
    catalog.workspace!.workView(workId),
    catalog.provider ?? '未配置模型',
  );
  @override
  Future<WorkspaceResult> load() async {
    catalog._apply(await catalog.gateway.load());
    return _view();
  }

  @override
  Future<WorkspaceResult> execute(NovelCommand command) async {
    if (catalog._reconnecting) {
      throw const GatewayFailure('正在更新连接，请完成后再保存。');
    }
    if (catalog.hasPending &&
        catalog.controllerFor(workId).pending?.requestId != command.requestId) {
      throw const GatewayFailure('其他操作的结果尚未确认，请先刷新或重试。');
    }
    final bound = LibraryCommand(
      requestId: command.requestId,
      expectedRevision: command.expectedRevision,
      target: CommandTarget.work(workId),
      operation: command.operation,
      payload: command.payload,
    );
    catalog._apply(await catalog.gateway.execute(bound));
    return _view();
  }

  @override
  void close() {}
}
