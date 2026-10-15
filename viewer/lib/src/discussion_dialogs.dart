import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'knowledge_details.dart';
import 'knowledge_metadata.dart';
import 'library_controller.dart';

class NewDiscussionDialog extends StatefulWidget {
  const NewDiscussionDialog({
    super.key,
    required this.controller,
    required this.workId,
  });
  final LibraryController controller;
  final String workId;
  @override
  State<NewDiscussionDialog> createState() => _NewDiscussionDialogState();
}

class _NewDiscussionDialogState extends State<NewDiscussionDialog> {
  final _title = TextEditingController();
  late final String _id = widget.controller.newKnowledgeId('discussion');
  String? _chapterId;
  String? _requestId;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请输入讨论名称。');
      return;
    }
    final saved = await widget.controller.createDiscussion(
      widget.workId,
      _id,
      _title.text,
      _chapterId,
    );
    if (!mounted) return;
    if (saved) {
      _finish();
    } else {
      setState(() => _requestId = widget.controller.pending?.requestId);
    }
  }

  void _finish() {
    widget.controller.selectDiscussion(widget.workId, _id);
    Navigator.pop(context);
  }

  Future<void> _resolve(bool retry) async {
    if (retry) {
      await widget.controller.retry();
    } else {
      await widget.controller.load();
    }
    if (!mounted) return;
    if (widget.controller.workspace!
        .work(widget.workId)
        .discussions
        .any((d) => d.id == _id)) {
      _finish();
    } else if (widget.controller.pending == null) {
      setState(() => _requestId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('新建讨论'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: ValueKey((widget.controller.busy, _requestId)),
                controller: _title,
                autofocus: true,
                readOnly: widget.controller.busy || _requestId != null,
                decoration: InputDecoration(
                  labelText: '讨论名称',
                  errorText: _error,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _chapterId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '讨论范围'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('整部作品')),
                  for (final c
                      in widget.controller.workspace!
                          .work(widget.workId)
                          .chapters)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        '第 ${c.number} 章 · ${c.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: widget.controller.busy || _requestId != null
                    ? null
                    : (id) => setState(() => _chapterId = id),
              ),
              if (widget.controller.errorForWork(widget.workId) != null)
                Text(widget.controller.errorForWork(widget.workId)!),
              if (_requestId != null) const Text('结果待确认，请刷新或重试原请求。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.controller.busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (widget.controller.errorForWork(widget.workId) != null ||
            _requestId != null)
          TextButton(
            onPressed: widget.controller.busy ? null : () => _resolve(false),
            child: const Text('刷新讨论'),
          ),
        if (_requestId != null)
          TextButton(
            onPressed: widget.controller.busy ? null : () => _resolve(true),
            child: const Text('重试原请求'),
          ),
        FilledButton(
          onPressed: widget.controller.canChangeCatalog && _requestId == null
              ? _save
              : null,
          child: const Text('创建讨论'),
        ),
      ],
    ),
  );
}

class AdoptDiscussionDialog extends StatefulWidget {
  const AdoptDiscussionDialog({
    super.key,
    required this.controller,
    required this.source,
    required this.edit,
  });
  final LibraryController controller;
  final DiscussionSource source;
  final bool edit;
  @override
  State<AdoptDiscussionDialog> createState() => _AdoptDiscussionDialogState();
}

class _AdoptDiscussionDialogState extends State<AdoptDiscussionDialog> {
  late final LibraryWorkspace _base = widget.controller.workspace!;
  late final _title = TextEditingController(
    text: _base
        .work(widget.source.workId)
        .discussions
        .firstWhere((d) => d.id == widget.source.discussionId)
        .title,
  );
  late final _body = TextEditingController(
    text: _base.discussionMessage(widget.source).body,
  );
  final _original = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  bool _alwaysRead = false;
  late final String _id = widget.controller.newKnowledgeId(
    widget.edit ? 'discussion-proposal' : 'discussion-document',
  );
  late final String _versionId = widget.controller.newKnowledgeId(
    'knowledge-version',
  );
  late String? _libraryId = _base.libraries.firstOrNull?.id;
  String _kind = 'reference';
  String? _chapterId;
  String? _error;
  String? _requestId;
  @override
  void initState() {
    super.initState();
    if (widget.edit) {
      final work = _base.work(widget.source.workId);
      final discussion = work.discussions.firstWhere(
        (d) => d.id == widget.source.discussionId,
      );
      _chapterId =
          work.chapters
              .where((c) => c.id == discussion.chapterId && c.body.isNotEmpty)
              .firstOrNull
              ?.id ??
          work.chapters.firstWhere((c) => c.body.isNotEmpty).id;
      _original.text = work.chapters.firstWhere((c) => c.id == _chapterId).body;
      _original.addListener(_selectionChanged);
    }
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _original.dispose();
    _description.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      bool saved;
      if (widget.edit) {
        final selection = _original.selection;
        final proposal = discussionEditProposal(
          workspace: _base,
          source: widget.source,
          id: _id,
          chapterId: _chapterId!,
          start: selection.start,
          end: selection.end,
          replacement: _body.text,
        );
        saved = await widget.controller.adoptDiscussionEdit(
          widget.source,
          proposal,
        );
      } else {
        saved = await widget.controller.adoptDiscussionKnowledge(
          source: widget.source,
          libraryId: _libraryId!,
          documentId: _id,
          version: KnowledgeVersion(
            id: _versionId,
            title: _title.text,
            kind: _kind,
            body: _body.text,
            description: _description.text,
            tags: knowledgeTags(_tags.text),
            alwaysRead: _alwaysRead,
            provenance: SourceProvenance(
              writer: SourceWriter(kind: 'author', id: 'author'),
              sources: [widget.source],
            ),
            associatedWorkId: widget.source.workId,
          ),
        );
      }
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => _requestId = widget.controller.pending?.requestId);
      }
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
    }
  }

  Future<void> _resolve(bool retry) async {
    if (retry) {
      await widget.controller.retry();
    } else {
      await widget.controller.load();
    }
    if (!mounted) return;
    if (_requestId != null &&
        widget.controller.workspace!.receipts.containsKey(_requestId)) {
      Navigator.pop(context);
    } else if (widget.controller.pending == null) {
      setState(() => _requestId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final frozen = widget.controller.busy || _requestId != null;
      return AlertDialog(
        title: Text(widget.edit ? '生成改稿提案' : '保存讨论成果'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('来源作品：${_base.work(widget.source.workId).title}'),
                if (widget.edit) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _chapterId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '目标章节'),
                    items: [
                      for (final c
                          in _base
                              .work(widget.source.workId)
                              .chapters
                              .where((c) => c.body.isNotEmpty))
                        DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '第 ${c.number} 章 · ${c.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (id) => setState(() {
                            _chapterId = id;
                            _original.text = _base
                                .work(widget.source.workId)
                                .chapters
                                .firstWhere((c) => c.id == id)
                                .body;
                          }),
                  ),
                  const Text('在原文中选择要替换的片段。选段外保留原文，提案需回正文审阅并接受。'),
                  TextField(
                    key: const ValueKey('discussion-original'),
                    controller: _original,
                    readOnly: true,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(labelText: '选择原文片段'),
                  ),
                  Text(
                    _original.selection.isValid &&
                            !_original.selection.isCollapsed
                        ? '已选中原文片段'
                        : '尚未选择片段',
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _libraryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '目标知识库'),
                    items: [
                      for (final l in _base.libraries)
                        DropdownMenuItem(
                          value: l.id,
                          child: Text(l.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (id) => setState(() => _libraryId = id),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: '成果身份'),
                    items: [
                      for (final kind in ['reference', 'setting', 'plan'])
                        DropdownMenuItem(
                          value: kind,
                          child: Text(knowledgeKind(kind)),
                        ),
                    ],
                    onChanged: frozen
                        ? null
                        : (kind) => setState(() => _kind = kind!),
                  ),
                  TextField(
                    key: ValueKey(('adopt-title', frozen)),
                    controller: _title,
                    readOnly: frozen,
                    decoration: const InputDecoration(labelText: '资料标题'),
                  ),
                  const Text('保存后仍需在知识库中明确采用资料版本，才会进入作品上下文。'),
                  const SizedBox(height: 16),
                  KnowledgeMetadataEditor(
                    description: _description,
                    tags: _tags,
                    alwaysRead: _alwaysRead,
                    editable: !frozen,
                    onAlwaysReadChanged: (value) =>
                        setState(() => _alwaysRead = value),
                  ),
                ],
                // Recreate Web semantics when readonly changes; retain the draft.
                KeyedSubtree(
                  key: ValueKey(('adopt-body', frozen)),
                  child: TextField(
                    key: const ValueKey('discussion-result'),
                    controller: _body,
                    readOnly: frozen,
                    minLines: 3,
                    maxLines: 7,
                    decoration: InputDecoration(
                      labelText: widget.edit ? '替换文本' : '成果内容',
                    ),
                  ),
                ),
                if (_error != null) Text(_error!),
                if (widget.controller.errorForWork(widget.source.workId) !=
                    null)
                  Text(widget.controller.errorForWork(widget.source.workId)!),
                if (_requestId != null) const Text('结果待确认，成果内容已保留。请刷新或重试原请求。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.controller.busy
                ? null
                : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (widget.controller.errorForWork(widget.source.workId) != null ||
              _requestId != null)
            TextButton(
              onPressed: widget.controller.busy ? null : () => _resolve(false),
              child: const Text('刷新讨论'),
            ),
          if (_requestId != null)
            TextButton(
              onPressed: widget.controller.busy ? null : () => _resolve(true),
              child: const Text('重试原请求'),
            ),
          FilledButton(
            onPressed: widget.controller.canChangeCatalog && _requestId == null
                ? _save
                : null,
            child: Text(widget.edit ? '保存待接受提案' : '保存成果'),
          ),
        ],
      );
    },
  );
}
