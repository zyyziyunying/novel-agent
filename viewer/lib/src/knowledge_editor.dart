import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'knowledge_details.dart';
import 'library_controller.dart';

void editKnowledge(
  BuildContext context,
  LibraryController controller,
  KnowledgeLibrary library,
  KnowledgeDocument? document,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _KnowledgeEditor(
    controller: controller,
    library: library,
    document: document,
  ),
);

class _SourceInput {
  _SourceInput(this.kind, String value)
    : field = TextEditingController(text: value);
  String kind;
  final TextEditingController field;
  void dispose() => field.dispose();
}

class _KnowledgeEditor extends StatefulWidget {
  const _KnowledgeEditor({
    required this.controller,
    required this.library,
    required this.document,
  });
  final LibraryController controller;
  final KnowledgeLibrary library;
  final KnowledgeDocument? document;
  @override
  State<_KnowledgeEditor> createState() => _KnowledgeEditorState();
}

class _KnowledgeEditorState extends State<_KnowledgeEditor> {
  final title = TextEditingController();
  final body = TextEditingController();
  final List<_SourceInput> sources = [];
  List<DiscussionSource> discussionSources = [];
  late final String documentId;
  String? baseVersionId;
  String kind = 'reference';
  String? associatedWorkId;
  String? requestId;
  String? validation;
  LibraryController get controller => widget.controller;
  KnowledgeDocument? get current => controller.workspace!
      .library(widget.library.id)
      .documents
      .where((d) => d.id == documentId)
      .firstOrNull;
  bool get stale => current?.head != baseVersionId;

  @override
  void initState() {
    super.initState();
    documentId = widget.document?.id ?? controller.newKnowledgeId('document');
    fill(widget.document?.current);
  }

  void fill(KnowledgeVersion? version) {
    baseVersionId = version?.id;
    title.text = version?.title ?? '';
    body.text = version?.body ?? '';
    kind = version?.kind ?? 'reference';
    associatedWorkId = version?.associatedWorkId;
    for (final source in sources) {
      source.dispose();
    }
    sources.clear();
    for (final source
        in version?.provenance.sources.whereType<ExternalSource>() ??
            <ExternalSource>[]) {
      sources.add(_SourceInput(source.kind, source.reference));
    }
    discussionSources =
        version?.provenance.sources.whereType<DiscussionSource>().toList() ??
        [];
    if (version == null) sources.add(_SourceInput('author', '作者手动录入'));
    validation = null;
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
      setState(() => validation = '资料标题和正文不能为空。');
      return;
    }
    late KnowledgeVersion version;
    try {
      version = KnowledgeVersion(
        id: controller.newKnowledgeId('knowledge-version'),
        title: title.text,
        kind: kind,
        body: body.text,
        provenance: SourceProvenance(
          writer: SourceWriter(kind: 'author', id: 'local-author'),
          sources: [
            for (final source in sources)
              ExternalSource(kind: source.kind, reference: source.field.text),
            ...discussionSources,
          ],
        ),
        associatedWorkId: associatedWorkId,
      );
    } on FormatException {
      setState(() => validation = '请保留至少一个有效来源；网页需填写完整 HTTP(S) 地址。');
      return;
    }
    final saved = await controller.saveKnowledgeDocument(
      libraryId: widget.library.id,
      documentId: documentId,
      expectedVersionId: baseVersionId,
      version: version,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => requestId = controller.pending?.requestId);
    }
  }

  Future<void> resolve(bool retry) async {
    if (retry) {
      await controller.retry();
    } else {
      await controller.load();
    }
    if (!mounted) return;
    if (requestId != null &&
        controller.workspace!.receipts.containsKey(requestId)) {
      Navigator.pop(context);
    } else if (controller.pending == null) {
      setState(() => requestId = null);
    }
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    for (final source in sources) {
      source.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final editable = !controller.busy && requestId == null;
      return AlertDialog(
        title: Text(widget.document == null ? '新增资料' : '编辑资料'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('目标知识库：${widget.library.name}'),
                const Text('保存只新增资料版本；作品需要另行采用，正文和派生记忆不会随之改变。'),
                if (stale) ...[
                  const Text('服务端资料版本已变化，本地编辑已保留。可查看后加载最新版，或保留草稿另行整理。'),
                  TextButton(
                    onPressed: editable
                        ? () => setState(() => fill(current?.current))
                        : null,
                    child: const Text('放弃草稿并加载最新版'),
                  ),
                ],
                TextField(
                  controller: title,
                  readOnly: !editable,
                  decoration: const InputDecoration(labelText: '资料标题'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  key: ValueKey('kind-$baseVersionId'),
                  decoration: const InputDecoration(labelText: '资料身份'),
                  items: [
                    for (final k in ['reference', 'setting', 'plan'])
                      DropdownMenuItem(value: k, child: Text(knowledgeKind(k))),
                  ],
                  onChanged: editable
                      ? (value) => setState(() => kind = value!)
                      : null,
                ),
                TextField(
                  controller: body,
                  readOnly: !editable,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(labelText: '资料正文'),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('associated-$baseVersionId'),
                  initialValue: associatedWorkId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '来源关联作品（可选，不自动采用）',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('独立资料，无作品关联'),
                    ),
                    for (final work in controller.workspace!.works)
                      DropdownMenuItem(
                        value: work.id,
                        child: Text(
                          work.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: editable
                      ? (value) => setState(
                          () => associatedWorkId = value == '' ? null : value,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                const Text('原始来源'),
                for (final source in sources)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButton<String>(
                          value: source.kind,
                          items: const [
                            DropdownMenuItem(
                              value: 'author',
                              child: Text('作者'),
                            ),
                            DropdownMenuItem(value: 'web', child: Text('网页')),
                            DropdownMenuItem(value: 'file', child: Text('文件')),
                          ],
                          onChanged: editable
                              ? (value) => setState(() => source.kind = value!)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: source.field,
                            readOnly: !editable,
                            decoration: const InputDecoration(
                              labelText: '来源地址或说明',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '移除此来源',
                          onPressed: editable
                              ? () => setState(() {
                                  sources.remove(source);
                                  source.dispose();
                                })
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                for (final source in discussionSources)
                  Text(
                    '保留讨论来源：${source.workId} / ${source.discussionId} / ${source.messageId}',
                  ),
                TextButton(
                  onPressed: editable
                      ? () => setState(
                          () => sources.add(_SourceInput('author', '')),
                        )
                      : null,
                  child: const Text('添加来源'),
                ),
                if (validation != null) Text(validation!),
                if (controller.error != null) Text(controller.error!),
                if (requestId != null) const Text('结果尚未确认，资料编辑已保留。请刷新或用原请求重试。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: controller.busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (controller.error != null || requestId != null)
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
            onPressed:
                controller.canChangeCatalog && requestId == null && !stale
                ? save
                : null,
            child: const Text('保存资料版本'),
          ),
        ],
      );
    },
  );
}
