import 'package:flutter/foundation.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'gateway.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.gateway, {String requestNamespace = 'work'})
    : _session = '$requestNamespace-${DateTime.now().microsecondsSinceEpoch}';
  final NovelGateway gateway;
  Workspace? workspace;
  String provider = '';
  String? error;
  bool busy = false;
  NovelCommand? pending;
  NovelCommand? lastConfirmedCommand;
  final Map<String, ({String requestId, String body, String? head})>
  _chapterSaves = {};
  int _sequence = 0;
  final String _session;

  ({String requestId, String body, String? head})? chapterSave(
    String chapterId,
  ) => _chapterSaves[chapterId];

  Future<bool> load() => _run(() async {
    final result = await gateway.load();
    _apply(result);
    if (pending != null &&
        result.workspace.receipts.containsKey(pending!.requestId)) {
      _confirm(pending!);
      pending = null;
    }
  });

  Future<bool> act(String operation, [Json payload = const {}]) async {
    if (busy || workspace == null || pending != null) return false;
    return _run(() async {
      final command = NovelCommand(
        requestId: '$_session-${++_sequence}',
        expectedRevision: workspace!.revision,
        operation: operation,
        payload: payload,
      );
      await _submit(command);
    });
  }

  Future<bool> retry() async {
    if (busy || pending == null) return false;
    return _run(() => _submit(pending!));
  }

  Future<void> _submit(NovelCommand command) async {
    try {
      _apply(await gateway.execute(command));
      _confirm(command);
      pending = null;
    } on GatewayFailure catch (failure) {
      // Central refresh can observe the commit before this connection fails.
      if (workspace!.receipts.containsKey(command.requestId)) {
        _confirm(command);
        pending = null;
        error = null;
        return;
      }
      pending = failure.uncertain ? command : null;
      rethrow;
    }
  }

  void _confirm(NovelCommand command) {
    lastConfirmedCommand = command;
    if (command.operation != 'saveChapter') return;
    final chapter = workspace!.chapters
        .where((c) => c.id == command.payload['chapterId'])
        .firstOrNull;
    if (chapter != null) {
      _chapterSaves[chapter.id] = (
        requestId: command.requestId,
        body: command.payload['body'],
        // A later, different server draft still requires an explicit conflict.
        head: chapter.body == command.payload['body'] ? chapter.head : null,
      );
    }
  }

  void _apply(WorkspaceResult result) {
    if (workspace == null || result.workspace.revision >= workspace!.revision) {
      workspace = result.workspace;
    }
    provider = result.provider;
  }

  /// Refresh a work-local view without replacing its draft or request state.
  void update(WorkspaceResult result) {
    _apply(result);
    if (pending != null &&
        workspace!.receipts.containsKey(pending!.requestId)) {
      _confirm(pending!);
      pending = null;
      error = null;
    }
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() work) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work();
      return true;
    } on GatewayFailure catch (failure) {
      error = failure.message;
    } on FormatException {
      error = '输入内容不符合工作台要求，请检查后重试。';
    } on Object {
      error = '无法完成操作，请刷新作品检查当前状态。';
    } finally {
      busy = false;
      notifyListeners();
    }
    return false;
  }

  @override
  void dispose() {
    gateway.close();
    super.dispose();
  }
}
