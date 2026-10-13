import 'package:flutter/material.dart';

import 'controller.dart';

class CreateChapterDialog extends StatefulWidget {
  const CreateChapterDialog({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  State<CreateChapterDialog> createState() => _CreateChapterDialogState();
}

class _CreateChapterDialogState extends State<CreateChapterDialog> {
  final _chapterId = 'manual-chapter-${DateTime.now().microsecondsSinceEpoch}';
  late final TextEditingController _title;
  String? _validation;
  String? _requestId;
  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: '第${controller.workspace!.chapters.length + 1}章',
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _validation = '章节标题不能为空。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _validation = null);
    final saved = await controller.act('createChapter', {
      'chapterId': _chapterId,
      'title': _title.text.trim(),
    });
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _requestId = controller.pending?.requestId);
    }
  }

  Future<void> _resolve({required bool retry}) async {
    FocusScope.of(context).unfocus();
    if (retry) {
      await controller.retry();
    } else {
      await controller.load();
    }
    if (!mounted) return;
    if (_requestId != null &&
        controller.workspace!.receipts.containsKey(_requestId)) {
      Navigator.pop(context);
    } else if (controller.pending == null) {
      setState(() => _requestId = null);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('新建章节'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              readOnly: controller.busy || _requestId != null,
              decoration: InputDecoration(
                labelText: '章节标题',
                errorText: _validation,
              ),
            ),
            const SizedBox(height: 12),
            const Text('创建空白章节，随后可直接输入正文并保存。'),
            if (controller.error != null) Text(controller.error!),
            if (_requestId != null) const Text('结果尚未确认，标题已保留。请刷新或重试。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: controller.busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (controller.error != null || _requestId != null)
          TextButton(
            onPressed: controller.busy ? null : () => _resolve(retry: false),
            child: const Text('刷新作品'),
          ),
        if (_requestId != null)
          TextButton(
            onPressed: controller.busy ? null : () => _resolve(retry: true),
            child: const Text('重试章节操作'),
          ),
        FilledButton(
          onPressed: !controller.busy && controller.pending == null
              ? _save
              : null,
          child: const Text('创建章节'),
        ),
      ],
    ),
  );
}
