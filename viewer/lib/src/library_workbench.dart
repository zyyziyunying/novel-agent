import 'package:flutter/material.dart';

import 'library_controller.dart';
import 'knowledge_panel.dart';
import 'workbench.dart';
import 'discussion_panel.dart';
import 'connection_settings.dart';

class LibraryWorkbench extends StatelessWidget {
  const LibraryWorkbench({super.key, required this.controller});
  final LibraryController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final workspace = controller.workspace;
      final connection = AgentConnectionSettings.maybeOf(context);
      final errorWork = workspace?.works
          .where((work) => work.id == controller.errorWorkId)
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(
          title: const Text('小说工作台'),
          actions: [
            if (connection != null)
              IconButton(
                tooltip: '连接设置',
                onPressed: connection.canOpen
                    ? () => connection.open(context)
                    : null,
                icon: const Icon(Icons.settings_ethernet),
              ),
            IconButton(
              tooltip: controller.showingDiscussion ? '返回正文' : '持续讨论',
              onPressed: () =>
                  controller.showDiscussion(!controller.showingDiscussion),
              icon: Icon(
                controller.showingDiscussion
                    ? Icons.edit_note
                    : Icons.forum_outlined,
              ),
            ),
            IconButton(
              tooltip: controller.showingKnowledge ? '返回正文' : '管理知识库',
              onPressed: () =>
                  controller.showKnowledge(!controller.showingKnowledge),
              icon: Icon(
                controller.showingKnowledge
                    ? Icons.edit_note
                    : Icons.library_books,
              ),
            ),
            if (controller.provider != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    controller.provider!.startsWith('fixture/')
                        ? '本地演示'
                        : 'DeepSeek',
                  ),
                ),
              ),
            IconButton(
              tooltip: '刷新作品',
              onPressed: controller.busy ? null : controller.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (controller.busy) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(controller.selectedId),
                        initialValue: controller.selectedId,
                        decoration: const InputDecoration(labelText: '作品'),
                        hint: const Text('尚无作品'),
                        isExpanded: true,
                        items: [
                          for (final work in workspace?.works ?? [])
                            DropdownMenuItem(
                              value: work.id,
                              child: Text(
                                work.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (workspace?.works.isEmpty ?? true)
                            ? null
                            : (id) => controller.select(id!),
                      ),
                    ),
                    IconButton(
                      tooltip: '创建作品',
                      icon: const Icon(Icons.add),
                      onPressed:
                          workspace != null && controller.canChangeCatalog
                          ? () => _name(context, null)
                          : null,
                    ),
                    IconButton(
                      tooltip: '重命名作品',
                      icon: const Icon(Icons.drive_file_rename_outline),
                      onPressed:
                          controller.selectedId != null &&
                              controller.canChangeCatalog
                          ? () => _name(context, controller.selectedId)
                          : null,
                    ),
                  ],
                ),
              ),
              if (!controller.modelAvailable && workspace != null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('未配置模型；正文保存、知识库管理与资料采用仍可使用。'),
                ),
              if (controller.error != null &&
                  (errorWork == null || errorWork.id == controller.selectedId))
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(controller.error!),
                ),
              if (controller.error != null &&
                  errorWork != null &&
                  errorWork.id != controller.selectedId)
                TextButton(
                  onPressed: () => controller.select(errorWork.id),
                  child: Text('${errorWork.title}：操作失败，返回查看'),
                ),
              if (controller.pending != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('目录或资料操作的结果尚未确认。'),
                    TextButton(
                      onPressed: controller.busy ? null : controller.retry,
                      child: const Text('重试作品操作'),
                    ),
                  ],
                ),
              for (final work in workspace?.works ?? [])
                if (work.id != controller.selectedId &&
                    (controller.controllerFor(work.id).busy ||
                        controller.controllerFor(work.id).pending != null ||
                        controller.controllerFor(work.id).error != null))
                  TextButton(
                    onPressed: () => controller.select(work.id),
                    child: Text(
                      '${work.title}：${controller.controllerFor(work.id).busy
                          ? '操作进行中'
                          : controller.controllerFor(work.id).pending != null
                          ? '结果待确认'
                          : '操作失败，查看详情'}',
                    ),
                  ),
              Expanded(
                child: workspace == null
                    ? Center(
                        child: FilledButton(
                          onPressed: controller.busy ? null : controller.load,
                          child: const Text('连接 Agent'),
                        ),
                      )
                    : IndexedStack(
                        index: controller.showingKnowledge
                            ? 1
                            : controller.showingDiscussion
                            ? 2
                            : 0,
                        children: [
                          workspace.works.isEmpty
                              ? Center(
                                  child: FilledButton(
                                    onPressed: controller.canChangeCatalog
                                        ? () => _name(context, null)
                                        : null,
                                    child: const Text('创建第一部作品'),
                                  ),
                                )
                              : IndexedStack(
                                  index: workspace.works.indexWhere(
                                    (w) => w.id == controller.selectedId,
                                  ),
                                  children: [
                                    for (final work in workspace.works)
                                      NovelWorkbench(
                                        key: ValueKey(work.id),
                                        controller: controller.controllerFor(
                                          work.id,
                                        ),
                                        embedded: true,
                                      ),
                                  ],
                                ),
                          KnowledgePanel(controller: controller),
                          workspace.works.isEmpty
                              ? const Center(child: Text('请先创建作品，再开始讨论。'))
                              : IndexedStack(
                                  index: workspace.works.indexWhere(
                                    (w) => w.id == controller.selectedId,
                                  ),
                                  children: [
                                    for (final work in workspace.works)
                                      DiscussionPanel(
                                        key: ValueKey('discussion-${work.id}'),
                                        controller: controller,
                                        workId: work.id,
                                      ),
                                  ],
                                ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  void _name(BuildContext context, String? workId) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WorkNameDialog(controller: controller, workId: workId),
  );
}

class _WorkNameDialog extends StatefulWidget {
  const _WorkNameDialog({required this.controller, this.workId});
  final LibraryController controller;
  final String? workId;
  @override
  State<_WorkNameDialog> createState() => _WorkNameDialogState();
}

class _WorkNameDialogState extends State<_WorkNameDialog> {
  late final TextEditingController _title;
  late final String _id;
  String? _requestId;
  String? _validation;
  LibraryController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    _id = widget.workId ?? controller.newWorkId();
    _title = TextEditingController(
      text: widget.workId == null ? '' : controller.workspace!.work(_id).title,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _validation = '作品名称不能为空。');
      return;
    }
    FocusScope.of(context).unfocus();
    final saved = widget.workId == null
        ? await controller.createWork(_id, _title.text)
        : await controller.renameWork(_id, _title.text);
    if (!mounted) return;
    if (saved) {
      controller.select(_id);
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
      controller.select(_id);
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
      title: Text(widget.workId == null ? '创建作品' : '重命名作品'),
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
                labelText: '作品名称',
                errorText: _validation,
              ),
            ),
            if (controller.errorForWork(widget.workId) != null)
              Text(controller.errorForWork(widget.workId)!),
            if (_requestId != null) const Text('结果尚未确认，名称已保留。请刷新或重试。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: controller.busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (controller.errorForWork(widget.workId) != null ||
            _requestId != null)
          TextButton(
            onPressed: controller.busy ? null : () => _resolve(retry: false),
            child: const Text('刷新作品'),
          ),
        if (_requestId != null)
          TextButton(
            onPressed: controller.busy ? null : () => _resolve(retry: true),
            child: const Text('重试作品操作'),
          ),
        FilledButton(
          onPressed: controller.canChangeCatalog && _requestId == null
              ? _save
              : null,
          child: const Text('保存名称'),
        ),
      ],
    ),
  );
}
