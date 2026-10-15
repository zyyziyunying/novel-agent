import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'connection_settings.dart';
import 'knowledge_details.dart';
import 'knowledge_metadata.dart';
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
  final description = TextEditingController();
  final tags = TextEditingController();
  bool alwaysRead = false;
  final formScroll = ScrollController();
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
    description.text = version?.description ?? '';
    tags.text = version?.tags.join('，') ?? '';
    alwaysRead = version?.alwaysRead ?? false;
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
        description: description.text,
        tags: knowledgeTags(tags.text),
        alwaysRead: alwaysRead,
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
    } on FormatException catch (error) {
      setState(() => validation = error.message.toString());
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => validation = null);
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
    FocusScope.of(context).unfocus();
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
    description.dispose();
    tags.dispose();
    formScroll.dispose();
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
      final connection = AgentConnectionSettings.maybeOf(context);
      final operationError = controller.errorForWork(associatedWorkId);
      final messages = [
        ?(validation ?? operationError),
        if (requestId != null) '结果尚未确认，资料编辑已保留。请刷新或用原请求重试。',
      ];
      final message = messages.isEmpty ? null : messages.join('\n');
      return AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        title: Text(widget.document == null ? '新增资料' : '编辑资料'),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        content: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: SizedBox(
            width: 680,
            child: Scrollbar(
              controller: formScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('knowledge-editor-form'),
                controller: formScroll,
                padding: const EdgeInsets.fromLTRB(0, 4, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '目标知识库：${widget.library.name}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '保存为新版本，作品当前采用的版本保持不变。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    if (stale) ...[
                      const Text('服务端资料版本已变化，本地编辑已保留。可查看后加载最新版，或保留草稿另行整理。'),
                      TextButton(
                        onPressed: editable
                            ? () => setState(() => fill(current?.current))
                            : null,
                        child: const Text('放弃草稿并加载最新版'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      // A nested dialog can detach the Web DOM editor. Recreate
                      // it when readOnly changes; controllers retain the draft.
                      key: ValueKey(('title', editable)),
                      controller: title,
                      readOnly: !editable,
                      decoration: const InputDecoration(labelText: '资料标题'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      isExpanded: true,
                      key: ValueKey('kind-$baseVersionId'),
                      decoration: const InputDecoration(labelText: '资料身份'),
                      items: [
                        for (final k in ['reference', 'setting', 'plan'])
                          DropdownMenuItem(
                            value: k,
                            child: Text(knowledgeKind(k)),
                          ),
                      ],
                      onChanged: editable
                          ? (value) => setState(() => kind = value!)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    KnowledgeMetadataEditor(
                      description: description,
                      tags: tags,
                      alwaysRead: alwaysRead,
                      editable: editable,
                      onAlwaysReadChanged: (value) =>
                          setState(() => alwaysRead = value),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: ValueKey(('body', editable)),
                      controller: body,
                      readOnly: !editable,
                      minLines: 6,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: '资料正文',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
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
                              () =>
                                  associatedWorkId = value == '' ? null : value,
                            )
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text('原始来源', style: Theme.of(context).textTheme.titleSmall),
                    for (final source in sources)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                DropdownButton<String>(
                                  value: source.kind,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'author',
                                      child: Text('作者'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'web',
                                      child: Text('网页'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'file',
                                      child: Text('文件'),
                                    ),
                                  ],
                                  onChanged: editable
                                      ? (value) =>
                                            setState(() => source.kind = value!)
                                      : null,
                                ),
                                const Spacer(),
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
                            const SizedBox(height: 8),
                            TextField(
                              key: ValueKey((source, editable)),
                              controller: source.field,
                              readOnly: !editable,
                              minLines: 2,
                              maxLines: null,
                              decoration: const InputDecoration(
                                labelText: '来源地址或说明',
                                alignLabelWithHint: true,
                              ),
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
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: 680,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (operationError != null && connection != null)
                      TextButton(
                        onPressed: connection.canOpen
                            ? () => connection.open(context)
                            : null,
                        child: const Text('连接设置'),
                      ),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    if (operationError != null || requestId != null)
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => resolve(false),
                        child: const Text('刷新资料'),
                      ),
                    if (requestId != null)
                      TextButton(
                        onPressed: controller.busy ? null : () => resolve(true),
                        child: const Text('重试资料操作'),
                      ),
                    FilledButton(
                      onPressed:
                          controller.canChangeCatalog &&
                              requestId == null &&
                              !stale
                          ? save
                          : null,
                      child: const Text('保存资料版本'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
