import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'knowledge_details.dart';
import 'knowledge_editor.dart';
import 'knowledge_metadata.dart';
import 'library_controller.dart';

class KnowledgePanel extends StatelessWidget {
  const KnowledgePanel({super.key, required this.controller});
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    final library = workspace.libraries
        .where((l) => l.id == controller.selectedLibraryId)
        .firstOrNull;
    final work = workspace.works
        .where((w) => w.id == controller.selectedId)
        .firstOrNull;
    final link = work?.knowledgeLinks
        .where((l) => l.libraryId == library?.id)
        .firstOrNull;
    final enabled = controller.canChangeCatalog;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('独立知识库', style: Theme.of(context).textTheme.headlineSmall),
        const Text('资料属于知识库。作品按整份资料采用固定版本；共享更新需各作品单独采用。'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('library-${library?.id}'),
                initialValue: library?.id,
                decoration: const InputDecoration(labelText: '知识库'),
                hint: const Text('尚无知识库'),
                isExpanded: true,
                items: [
                  for (final l in workspace.libraries)
                    DropdownMenuItem(
                      value: l.id,
                      child: Text(l.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: workspace.libraries.isEmpty
                    ? null
                    : (id) => controller.selectLibrary(id!),
              ),
            ),
            IconButton(
              tooltip: '创建知识库',
              onPressed: enabled ? () => _name(context, null) : null,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: '重命名知识库',
              onPressed: enabled && library != null
                  ? () => _name(context, library)
                  : null,
              icon: const Icon(Icons.drive_file_rename_outline),
            ),
          ],
        ),
        if (library != null) ...[
          const SizedBox(height: 12),
          if (work == null)
            const Text('可独立管理资料；创建作品后再关联和采用。')
          else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  '${work.title}：${link == null ? '未关联此库' : '已关联，采用 ${link.versions.length} 份资料'}',
                ),
                TextButton(
                  onPressed: enabled
                      ? () => controller.setKnowledgeLinks(work.id, [
                          for (final l in work.knowledgeLinks)
                            if (l.libraryId != library.id) l,
                          if (link == null)
                            LibraryLink(libraryId: library.id, versions: {}),
                        ])
                      : null,
                  child: Text(link == null ? '关联此知识库' : '取消关联'),
                ),
              ],
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: enabled
                    ? () => editKnowledge(context, controller, library, null)
                    : null,
                icon: const Icon(Icons.note_add),
                label: const Text('新增资料'),
              ),
            ],
          ),
          if (library.documents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('此知识库尚无资料。'),
            ),
          for (final document in library.documents)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.current.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${knowledgeKind(document.current.kind)} · 知识库最新：${knowledgeVersionLabel(document, document.head)}',
                    ),
                    SelectableText('资料 ID：${document.id}'),
                    KnowledgeMetadata(version: document.current),
                    if (link?.versions[document.id]
                        case final String adopted) ...[
                      Text(
                        '${work!.title} 已采用：${knowledgeVersionLabel(document, adopted)}${adopted != document.head ? ' · 有新版可采用' : ''}',
                      ),
                      if (adopted != document.head)
                        Text(
                          '采用版标题：${document.versions.firstWhere((v) => v.id == adopted).title}',
                        ),
                    ] else
                      Text(work == null ? '未采用到作品' : '${work.title} 尚未采用此资料'),
                    Text(
                      '写入者：${document.current.provenance.writer.kind} / ${document.current.provenance.writer.id}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () =>
                              _history(context, library, document, work?.id),
                          child: const Text('查看资料与历史'),
                        ),
                        TextButton(
                          onPressed: enabled
                              ? () => editKnowledge(
                                  context,
                                  controller,
                                  library,
                                  document,
                                )
                              : null,
                          child: const Text('编辑资料'),
                        ),
                        if (work != null && link != null) ...[
                          FilledButton(
                            onPressed:
                                enabled &&
                                    link.versions[document.id] != document.head
                                ? () => _adopt(
                                    work.id,
                                    library.id,
                                    document.id,
                                    document.head,
                                  )
                                : null,
                            child: const Text('采用最新版'),
                          ),
                          if (link.versions.containsKey(document.id))
                            TextButton(
                              onPressed: enabled
                                  ? () => _adopt(
                                      work.id,
                                      library.id,
                                      document.id,
                                      null,
                                    )
                                  : null,
                              child: const Text('停止采用'),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<bool> _adopt(
    String workId,
    String libraryId,
    String documentId,
    String? versionId,
  ) {
    final work = controller.workspace!.work(workId);
    return controller.setKnowledgeLinks(workId, [
      for (final link in work.knowledgeLinks)
        if (link.libraryId != libraryId)
          link
        else
          LibraryLink(
            libraryId: libraryId,
            versions: {
              for (final entry in link.versions.entries)
                if (entry.key != documentId) entry.key: entry.value,
              documentId: ?versionId,
            },
          ),
    ]);
  }

  void _history(
    BuildContext context,
    KnowledgeLibrary library,
    KnowledgeDocument document,
    String? workId,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _KnowledgeHistory(
      controller: controller,
      library: library,
      documentId: document.id,
      workId: workId,
    ),
  );
  void _name(BuildContext context, KnowledgeLibrary? library) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LibraryName(controller: controller, library: library),
      );
}

class _KnowledgeHistory extends StatefulWidget {
  const _KnowledgeHistory({
    required this.controller,
    required this.library,
    required this.documentId,
    required this.workId,
  });
  final LibraryController controller;
  final KnowledgeLibrary library;
  final String documentId;
  final String? workId;
  @override
  State<_KnowledgeHistory> createState() => _KnowledgeHistoryState();
}

class _KnowledgeHistoryState extends State<_KnowledgeHistory> {
  late String versionId = widget.library.documents
      .firstWhere((d) => d.id == widget.documentId)
      .head;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final document = controller.workspace!
          .library(widget.library.id)
          .documents
          .firstWhere((d) => d.id == widget.documentId);
      final work = widget.workId == null
          ? null
          : controller.workspace!.work(widget.workId!);
      final link = work?.knowledgeLinks
          .where((l) => l.libraryId == widget.library.id)
          .firstOrNull;
      return AlertDialog(
        title: Text('${widget.library.name} · 资料历史'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: versionId,
                  decoration: const InputDecoration(labelText: '资料版本'),
                  isExpanded: true,
                  items: [
                    for (final v in document.versions.reversed)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          '${knowledgeVersionLabel(document, v.id)}${v.id == document.head ? '（最新）' : ''}',
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => versionId = id!),
                ),
                const SizedBox(height: 16),
                KnowledgeDetails(
                  version: document.versions.firstWhere(
                    (v) => v.id == versionId,
                  ),
                ),
                if (work != null) Text('采用目标：${work.title}'),
                if (controller.errorForWork(widget.workId) != null)
                  Text(controller.errorForWork(widget.workId)!),
              ],
            ),
          ),
        ),
        actions: [
          if (link != null)
            FilledButton(
              onPressed:
                  controller.canChangeCatalog &&
                      link.versions[widget.documentId] != versionId
                  ? () async {
                      final saved = await controller.setKnowledgeLinks(
                        work!.id,
                        [
                          for (final l in work.knowledgeLinks)
                            if (l.libraryId != widget.library.id)
                              l
                            else
                              LibraryLink(
                                libraryId: l.libraryId,
                                versions: {
                                  ...l.versions,
                                  widget.documentId: versionId,
                                },
                              ),
                        ],
                      );
                      if (saved && context.mounted) Navigator.pop(context);
                    }
                  : null,
              child: const Text('采用此版本'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

class _LibraryName extends StatefulWidget {
  const _LibraryName({required this.controller, this.library});
  final LibraryController controller;
  final KnowledgeLibrary? library;
  @override
  State<_LibraryName> createState() => _LibraryNameState();
}

class _LibraryNameState extends State<_LibraryName> {
  late final id =
      widget.library?.id ?? widget.controller.newKnowledgeId('library');
  late final field = TextEditingController(text: widget.library?.name ?? '');
  String? requestId;
  String? validation;
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (field.text.trim().isEmpty) {
      setState(() => validation = '知识库名称不能为空。');
      return;
    }
    FocusScope.of(context).unfocus();
    final saved = widget.library == null
        ? await widget.controller.createLibrary(id, field.text)
        : await widget.controller.renameLibrary(id, field.text);
    if (!mounted) return;
    if (saved) {
      widget.controller.selectLibrary(id);
      Navigator.pop(context);
    } else {
      setState(() => requestId = widget.controller.pending?.requestId);
    }
  }

  Future<void> resolve(bool retry) async {
    FocusScope.of(context).unfocus();
    final controller = widget.controller;
    if (retry) {
      await controller.retry();
    } else {
      await controller.load();
    }
    if (!mounted) return;
    if (requestId != null &&
        controller.workspace!.receipts.containsKey(requestId)) {
      controller.selectLibrary(id);
      Navigator.pop(context);
    } else if (controller.pending == null) {
      setState(() => requestId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return AlertDialog(
        title: Text(widget.library == null ? '创建知识库' : '重命名知识库'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: field,
                autofocus: true,
                readOnly: controller.busy || requestId != null,
                decoration: InputDecoration(
                  labelText: '知识库名称',
                  errorText: validation,
                ),
              ),
              if (controller.errorForWork(null) != null)
                Text(controller.errorForWork(null)!),
              if (requestId != null) const Text('结果尚未确认，名称已保留。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: controller.busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (controller.errorForWork(null) != null)
            TextButton(
              onPressed: controller.busy ? null : () => resolve(false),
              child: const Text('刷新资料'),
            ),
          if (requestId != null)
            TextButton(
              onPressed: controller.busy ? null : () => resolve(true),
              child: const Text('重试资料操作'),
            ),
          FilledButton(
            onPressed: controller.canChangeCatalog && requestId == null
                ? save
                : null,
            child: const Text('保存知识库名称'),
          ),
        ],
      );
    },
  );
}
