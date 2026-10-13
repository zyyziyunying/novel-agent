import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'library_gateway.dart';

/// Available to the workbench and its open editing dialogs, so renewing a
/// session does not require discarding an editor to reach the app bar.
class AgentConnectionSettings extends InheritedWidget {
  const AgentConnectionSettings({
    super.key,
    required this.controller,
    required this.open,
    required super.child,
  });
  final LibraryController? controller;
  final void Function(BuildContext context) open;
  bool get canOpen => controller?.canReconnect ?? false;
  static AgentConnectionSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentConnectionSettings>();
  @override
  bool updateShouldNotify(AgentConnectionSettings oldWidget) =>
      controller != oldWidget.controller;
}

class ConnectionSettingsDialog extends StatefulWidget {
  const ConnectionSettingsDialog({
    super.key,
    required this.endpoint,
    required this.controller,
    required this.gatewayFactory,
  });
  final Uri endpoint;
  final LibraryController controller;
  final LibraryGateway Function(Uri, String) gatewayFactory;
  @override
  State<ConnectionSettingsDialog> createState() =>
      _ConnectionSettingsDialogState();
}

class _ConnectionSettingsDialogState extends State<ConnectionSettingsDialog> {
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_token.text.trim().isEmpty) {
      setState(() => _error = '请输入 Agent 本次启动显示的会话令牌。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final saved = await widget.controller.reconnect(
      widget.gatewayFactory(widget.endpoint, _token.text.trim()),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.error ?? '当前有操作进行中，请稍后更新连接。';
      });
    }
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接设置'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Agent 地址：${widget.endpoint}'),
            const SizedBox(height: 12),
            const Text('更新当前 Agent 的会话令牌，保留未保存草稿和待确认请求。'),
            const SizedBox(height: 20),
            TextField(
              controller: _token,
              autofocus: true,
              obscureText: true,
              readOnly: _busy,
              decoration: const InputDecoration(labelText: '工作台会话令牌'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? '正在连接…' : '更新连接'),
      ),
    ],
  );
}
