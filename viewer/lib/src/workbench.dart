import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'controller.dart';
import 'chapter_dialog.dart';
import 'library_controller.dart';
import 'library_gateway.dart';
import 'library_workbench.dart';
import 'knowledge_details.dart';
import 'connection_settings.dart';

class NovelApp extends StatefulWidget {
  const NovelApp({super.key, this.gatewayFactory});
  final LibraryGateway Function(Uri endpoint, String token)? gatewayFactory;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  final _endpoint = TextEditingController(
    text: const String.fromEnvironment(
      'NOVEL_AGENT_URL',
      defaultValue: 'http://127.0.0.1:4100',
    ),
  );
  final _token = TextEditingController(
    text: const String.fromEnvironment('NOVEL_AGENT_TOKEN'),
  );
  LibraryController? _controller;
  String? _error;
  bool _connecting = false;
  @override
  void initState() {
    super.initState();
    if (_token.text.isNotEmpty) _connect();
  }

  LibraryGateway _gateway(Uri endpoint, String token) =>
      widget.gatewayFactory?.call(endpoint, token) ??
      HttpLibraryGateway(endpoint: endpoint, token: token);

  Future<void> _connect() async {
    if (_connecting) return;
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    if (endpoint == null ||
        !{'http', 'https'}.contains(endpoint.scheme) ||
        !{'localhost', '127.0.0.1', '::1'}.contains(endpoint.host) ||
        _token.text.trim().isEmpty) {
      setState(() => _error = '请输入本地 Agent 地址及其显示的会话令牌。');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _connecting = true;
      _error = null;
    });
    final candidate = LibraryController(_gateway(endpoint, _token.text.trim()));
    final connected = await candidate.load();
    if (!mounted) {
      candidate.dispose();
      return;
    }
    setState(() {
      _connecting = false;
      if (connected) {
        _controller = candidate;
        _token.clear();
      } else {
        _error = candidate.error;
        candidate.dispose();
      }
    });
  }

  void _connectionSettings(BuildContext context) {
    if (!(_controller?.canReconnect ?? false)) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConnectionSettingsDialog(
        endpoint: Uri.parse(_endpoint.text.trim()),
        controller: _controller!,
        gatewayFactory: _gateway,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Novel Agent Lab',
    debugShowCheckedModeBanner: false,
    builder: (_, child) => AgentConnectionSettings(
      controller: _controller,
      open: _connectionSettings,
      child: child!,
    ),
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff335f57)),
      scaffoldBackgroundColor: const Color(0xfff6f5f0),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: _controller != null
        ? LibraryWorkbench(controller: _controller!)
        : Scaffold(
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.auto_stories_outlined, size: 48),
                      const SizedBox(height: 20),
                      const Text(
                        '小说工作台',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28),
                      ),
                      const SizedBox(height: 12),
                      const Text('连接本地 Agent，开始编辑、改稿和续写。'),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _endpoint,
                        readOnly: _connecting,
                        decoration: const InputDecoration(
                          labelText: 'Agent 地址',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _token,
                        obscureText: true,
                        readOnly: _connecting,
                        decoration: const InputDecoration(
                          labelText: '工作台会话令牌',
                          helperText: '启动 Agent 后在终端查看；此处填写本地会话令牌。',
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) Text(_error!),
                      FilledButton(
                        onPressed: _connecting ? null : _connect,
                        child: Text(_connecting ? '正在连接…' : '连接工作台'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

class NovelWorkbench extends StatefulWidget {
  const NovelWorkbench({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final WorkspaceController controller;
  final bool embedded;
  @override
  State<NovelWorkbench> createState() => _NovelWorkbenchState();
}

class _NovelWorkbenchState extends State<NovelWorkbench> {
  int _selected = 0;
  String? _lastCreationId;
  final _editorKey = GlobalKey();
  WorkspaceController get controller => widget.controller;
  bool get enabled => !controller.busy && controller.pending == null;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final workspace = controller.workspace;
      final confirmed = controller.lastConfirmedCommand;
      if (confirmed?.operation == 'createChapter' &&
          confirmed!.requestId != _lastCreationId &&
          workspace != null) {
        _lastCreationId = confirmed.requestId;
        final index = workspace.chapters.indexWhere(
          (c) => c.id == confirmed.payload['chapterId'],
        );
        if (index >= 0) _selected = index;
      }
      return Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: Text(workspace?.title ?? '小说工作台'),
                actions: [
                  if (controller.provider.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: Text(
                          controller.provider.startsWith('fixture/')
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
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (controller.pending != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('上次操作的结果尚未确认。刷新或用同一请求重试后再继续。'),
                      TextButton(
                        onPressed: controller.busy ? null : controller.retry,
                        child: const Text('重试上次操作'),
                      ),
                    ],
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 1120;
                          final selected = workspace.chapters.isEmpty
                              ? null
                              : _selected.clamp(
                                  0,
                                  workspace.chapters.length - 1,
                                );
                          final editor = workspace.chapters.isEmpty
                              ? const Center(child: Text('尚无正文'))
                              : IndexedStack(
                                  key: _editorKey,
                                  index: selected ?? 0,
                                  children: [
                                    for (final chapter in workspace.chapters)
                                      ChapterEditor(
                                        key: ValueKey(chapter.id),
                                        chapter: chapter,
                                        controller: controller,
                                      ),
                                  ],
                                );
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 224,
                                  child: _navigation(workspace),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(child: editor),
                                const VerticalDivider(width: 1),
                                SizedBox(
                                  width: 350,
                                  child: WorkspaceInspector(
                                    controller: controller,
                                    allowDocumentEditing: !widget.embedded,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: selected,
                                        decoration: const InputDecoration(
                                          labelText: '章节',
                                        ),
                                        isExpanded: true,
                                        hint: const Text('尚无章节'),
                                        items: [
                                          for (
                                            var i = 0;
                                            i < workspace.chapters.length;
                                            i++
                                          )
                                            DropdownMenuItem(
                                              value: i,
                                              child: Text(
                                                workspace.chapters[i].title,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: workspace.chapters.isEmpty
                                            ? null
                                            : (value) => setState(
                                                () => _selected = value ?? 0,
                                              ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '新建章节',
                                      onPressed: enabled
                                          ? _createChapter
                                          : null,
                                      icon: const Icon(Icons.add),
                                    ),
                                    IconButton(
                                      tooltip: '知识库与写作助手',
                                      icon: const Icon(
                                        Icons.library_books_outlined,
                                      ),
                                      onPressed: () => showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        showDragHandle: true,
                                        builder: (_) => SizedBox(
                                          height:
                                              MediaQuery.sizeOf(
                                                context,
                                              ).height *
                                              .85,
                                          child: ListenableBuilder(
                                            listenable: controller,
                                            builder: (_, _) =>
                                                WorkspaceInspector(
                                                  controller: controller,
                                                  showDocuments: true,
                                                  allowDocumentEditing:
                                                      !widget.embedded,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(child: editor),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _navigation(Workspace workspace) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text('正文', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      TextButton.icon(
        onPressed: enabled ? _createChapter : null,
        icon: const Icon(Icons.add),
        label: const Text('新建章节'),
      ),
      for (var i = 0; i < workspace.chapters.length; i++)
        ListTile(
          selected: i == _selected,
          title: Text(workspace.chapters[i].title),
          subtitle: workspace.chapters[i].needsReview
              ? const Text('待作者复查')
              : null,
          onTap: () => setState(() => _selected = i),
        ),
      const Divider(),
      const ListTile(title: Text('知识库')),
      for (final document in workspace.documents)
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(document.title),
          subtitle: Text(_kind(document.kind)),
          onTap: widget.embedded
              ? () => _viewDocument(context, document)
              : () => editDocument(context, controller, document),
        ),
      if (!widget.embedded)
        TextButton.icon(
          onPressed: enabled
              ? () => editDocument(context, controller, null)
              : null,
          icon: const Icon(Icons.add),
          label: const Text('添加资料'),
        ),
    ],
  );

  void _createChapter() => showDialog<void>(
    context: context,
    builder: (_) => CreateChapterDialog(controller: controller),
  );
}

class ChapterEditor extends StatefulWidget {
  const ChapterEditor({
    super.key,
    required this.chapter,
    required this.controller,
  });
  final Chapter chapter;
  final WorkspaceController controller;
  @override
  State<ChapterEditor> createState() => _ChapterEditorState();
}

class _ChapterEditorState extends State<ChapterEditor> {
  late final TextEditingController _body;
  late String _head;
  late String _original;
  String? _lastSaveId;
  bool get dirty => _body.text != _original;
  bool get conflict => _head != widget.chapter.head;
  bool get enabled =>
      !widget.controller.busy && widget.controller.pending == null;
  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.chapter.body);
    _head = widget.chapter.head;
    _original = widget.chapter.body;
    _lastSaveId = widget.controller.chapterSave(widget.chapter.id)?.requestId;
    _body.addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void didUpdateWidget(ChapterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final save = widget.controller.chapterSave(widget.chapter.id);
    final ownSave = save != null && save.requestId != _lastSaveId;
    _lastSaveId = save?.requestId;
    if (ownSave) {
      // Even an undo back to the old baseline is an edit after submission.
      _original = save.body;
      if (save.head != null) _head = save.head!;
    } else if (!dirty || _body.text == widget.chapter.body) {
      _head = widget.chapter.head;
      _original = widget.chapter.body;
      if (_body.text != _original) _body.text = _original;
    }
  }

  @override
  void dispose() {
    _body.removeListener(_changed);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.chapter.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              dirty
                  ? '有未保存草稿'
                  : '已保存 · ${_versionLabel(widget.chapter, _head)}',
            ),
            FilledButton.tonalIcon(
              onPressed:
                  enabled && dirty && !conflict && _body.text.trim().isNotEmpty
                  ? () => widget.controller.act('saveChapter', {
                      'chapterId': widget.chapter.id,
                      'body': _body.text,
                    })
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存正文'),
            ),
            OutlinedButton.icon(
              onPressed:
                  enabled &&
                      !dirty &&
                      !conflict &&
                      !_body.selection.isCollapsed &&
                      _body.selection.isValid
                  ? _proposeEdit
                  : null,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('改写选段'),
            ),
            PopupMenuButton<String>(
              tooltip: '历史版本',
              enabled: enabled && !dirty,
              onSelected: (versionId) => widget.controller.act(
                'restoreVersion',
                {'chapterId': widget.chapter.id, 'versionId': versionId},
              ),
              itemBuilder: (_) => [
                for (final (index, version)
                    in widget.chapter.versions.indexed.toList().reversed)
                  PopupMenuItem(
                    value: version.id,
                    enabled: version.id != widget.chapter.head,
                    child: Text(
                      version.id == widget.chapter.head
                          ? '第 ${index + 1} 版（当前）'
                          : '恢复第 ${index + 1} 版',
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Text('历史版本'),
              ),
            ),
          ],
        ),
        if (conflict)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              children: [
                const Text('服务端正文版本已变化，本地草稿已保留。'),
                TextButton(
                  onPressed: () {
                    _head = widget.chapter.head;
                    _original = widget.chapter.body;
                    _body.text = _original;
                  },
                  child: const Text('放弃草稿并加载新版本'),
                ),
              ],
            ),
          ),
        if (widget.chapter.needsReview)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('前文已修改，请检查本章是否仍使用旧事实。'),
                TextButton(
                  onPressed: enabled && !dirty
                      ? () => widget.controller.act('confirmReview', {
                          'chapterId': widget.chapter.id,
                        })
                      : null,
                  child: const Text('已复查，无需改动'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            key: ValueKey('body-${widget.chapter.id}'),
            controller: _body,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 18, height: 1.8),
            decoration: InputDecoration(
              hintText: '在这里写正文',
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.all(20),
              errorText: _body.text.trim().isEmpty ? '正文不能为空。' : null,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _proposeEdit() async {
    final selection = _body.selection;
    if (!selection.isValid || selection.isCollapsed || dirty) return;
    final instruction = await askInstruction(
      context,
      '改写选段',
      '按我的要求改写所选段落，保持选段外的正文和已有设定一致。',
    );
    if (instruction == null || !mounted) return;
    await widget.controller.act('proposeEdit', {
      'chapterId': widget.chapter.id,
      'start': selection.start,
      'end': selection.end,
      'instruction': instruction,
    });
  }
}

class WorkspaceInspector extends StatelessWidget {
  const WorkspaceInspector({
    super.key,
    required this.controller,
    this.showDocuments = false,
    this.allowDocumentEditing = true,
  });
  final WorkspaceController controller;
  final bool showDocuments;
  final bool allowDocumentEditing;
  @override
  Widget build(BuildContext context) {
    final workspace = controller.workspace!;
    final enabled = !controller.busy && controller.pending == null;
    final memory = workspace.currentMemory;
    final hasEmptyChapter = workspace.chapters.any(
      (c) => c.body.trim().isEmpty,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('写作助手', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          workspace.chapters.isEmpty
              ? '尚无正文，可以开始起草第一章'
              : workspace.memoryFresh
              ? '记忆与当前正文版本一致'
              : '记忆已失效，需要重建',
          style: TextStyle(
            color: workspace.memoryFresh
                ? const Color(0xff335f57)
                : Colors.deepOrange,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              enabled &&
                  !hasEmptyChapter &&
                  workspace.memoryFresh &&
                  !workspace.chapters.any((c) => c.needsReview)
              ? () async {
                  final instruction = await askInstruction(
                    context,
                    workspace.chapters.isEmpty ? '起草第一章' : '续写下一章',
                    workspace.chapters.isEmpty
                        ? '根据知识库中的设定起草第一章。请补充故事类型、主角和开篇场景。'
                        : '根据已有正文和知识库续写下一章，遵守人物的知情范围。',
                  );
                  if (instruction != null) {
                    await controller.act('proposeChapter', {
                      'instruction': instruction,
                    });
                  }
                }
              : null,
          icon: const Icon(Icons.edit_note),
          label: Text(workspace.chapters.isEmpty ? '起草第一章' : '起草下一章'),
        ),
        if (hasEmptyChapter) const Text('请先填写并保存空白章节，再重建记忆或起草下一章。'),
        OutlinedButton(
          onPressed: enabled && !hasEmptyChapter
              ? () => controller.act('rebuildMemory')
              : null,
          child: const Text('重建记忆'),
        ),
        if (workspace.chapters.any((c) => c.needsReview))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('后续章仍待复查，复查完成后可续写。'),
          ),
        const Divider(height: 32),
        Text('待接受提案', style: Theme.of(context).textTheme.titleMedium),
        if (!workspace.proposals.any((p) => p.status == 'pending'))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('AI 草稿将在这里等待你的决定。'),
          ),
        for (final proposal
            in workspace.proposals
                .where((p) => p.status == 'pending')
                .toList()
                .reversed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    proposal.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('基于作品 r${proposal.baseRevision} · ${proposal.provider}'),
                  const SizedBox(height: 8),
                  Text(
                    proposal.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton(
                    onPressed: () => _preview(context, workspace, proposal),
                    child: const Text('查看修改与上下文'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: enabled
                            ? () => controller.act('acceptProposal', {
                                'proposalId': proposal.id,
                              })
                            : null,
                        child: const Text('接受'),
                      ),
                      OutlinedButton(
                        onPressed: enabled
                            ? () => controller.act('rejectProposal', {
                                'proposalId': proposal.id,
                              })
                            : null,
                        child: const Text('拒绝'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 32),
        Text('派生记忆', style: Theme.of(context).textTheme.titleMedium),
        if (memory == null) const Text('当前版本还没有可用的记忆快照。'),
        if (memory != null) ...[
          Text('快照 ${memory.id}'),
          for (final fact in memory.facts)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fact.text),
                  Text(
                    _chapterVersionLabel(
                      workspace,
                      fact.chapterId,
                      fact.versionId,
                    ),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    '原文：“${fact.evidence}”',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
        if (showDocuments) ...[
          const Divider(height: 32),
          const Text('知识库'),
          for (final d in workspace.documents)
            ListTile(
              title: Text(d.title),
              subtitle: Text(_kind(d.kind)),
              onTap: allowDocumentEditing
                  ? () => editDocument(context, controller, d)
                  : () => _viewDocument(context, d),
            ),
          if (allowDocumentEditing)
            TextButton(
              onPressed: enabled
                  ? () => editDocument(context, controller, null)
                  : null,
              child: const Text('添加资料'),
            ),
        ],
      ],
    );
  }

  void _preview(BuildContext context, Workspace workspace, Proposal proposal) {
    final old = workspace.chapters
        .where((c) => c.id == proposal.chapterId)
        .firstOrNull;
    final baseVersion = old?.versions
        .where((v) => v.id == proposal.baseHeads[old.id])
        .firstOrNull;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(proposal.title),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (baseVersion != null) ...[
                  const Text(
                    '修改前',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(baseVersion.body),
                  const Divider(height: 28),
                ],
                const Text(
                  '提案正文',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText(proposal.body),
                const Divider(height: 28),
                const Text(
                  '此次使用的上下文',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (proposal.context['discussionSource'] case final Json source)
                  SelectableText(
                    '讨论来源：${source['workId']} / ${source['discussionId']} / ${source['messageId']}',
                  )
                else
                  Text('作者要求：${proposal.context['authorInstruction']}'),
                if (proposal.baseHeads.isEmpty) const Text('正文版本：无已有章节'),
                for (final entry in proposal.baseHeads.entries)
                  Text(
                    '正文版本：${_chapterVersionLabel(workspace, entry.key, entry.value)}',
                  ),
                Text(
                  '记忆：${(proposal.context['memory'] as Json?)?['id'] ?? '未使用可用记忆'}',
                ),
                if (proposal.context['knowledgeDocuments']
                    case final List manifest)
                  for (final d in manifest) ...[
                    SelectableText(
                      '知识库：${d['libraryName'] ?? d['libraryId']}（${d['libraryId']}）\n资料 ID：${d['documentId']} · 采用版本：${d['versionId']}',
                    ),
                    KnowledgeDetails(
                      version: KnowledgeVersion.fromJson(d['version']),
                    ),
                    const SizedBox(height: 12),
                  ]
                else
                  for (final d in (proposal.context['documents'] as List))
                    Text('资料：${d['title']}（${_kind(d['kind'])}）\n${d['body']}'),
                if (proposal.context['selection'] != null)
                  Text('选段：${proposal.context['selection']['text']}'),
                Text('模型 usage：${proposal.usage}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

String _versionLabel(Chapter chapter, String versionId) {
  final index = chapter.versions.indexWhere((v) => v.id == versionId);
  return index < 0 ? '版本不可用' : '第 ${index + 1} 版';
}

String _chapterVersionLabel(
  Workspace workspace,
  String chapterId,
  String versionId,
) {
  final chapter = workspace.chapters
      .where((c) => c.id == chapterId)
      .firstOrNull;
  return chapter == null
      ? '章节不可用'
      : '第 ${chapter.number} 章 · ${chapter.title} · ${_versionLabel(chapter, versionId)}';
}

String _kind(String kind) => switch (kind) {
  'setting' => '作者设定',
  'plan' => '未来计划',
  _ => '外部参考',
};

void _viewDocument(BuildContext context, SourceDocument document) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document.title),
        content: SingleChildScrollView(child: SelectableText(document.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

Future<String?> askInstruction(
  BuildContext context,
  String title,
  String initial,
) => showDialog<String>(
  context: context,
  builder: (_) => _InstructionDialog(title: title, initial: initial),
);

class _InstructionDialog extends StatefulWidget {
  const _InstructionDialog({required this.title, required this.initial});
  final String title;
  final String initial;
  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
  late final TextEditingController field;
  @override
  void initState() {
    super.initState();
    field = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: TextField(
        controller: field,
        minLines: 3,
        maxLines: 6,
        autofocus: true,
        decoration: const InputDecoration(labelText: '作者要求'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (field.text.trim().isNotEmpty) {
            Navigator.pop(context, field.text.trim());
          }
        },
        child: const Text('生成提案'),
      ),
    ],
  );
}

Future<void> editDocument(
  BuildContext context,
  WorkspaceController controller,
  SourceDocument? document,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DocumentDialog(controller: controller, document: document),
  );
}

class _DocumentDialog extends StatefulWidget {
  const _DocumentDialog({required this.controller, this.document});
  final WorkspaceController controller;
  final SourceDocument? document;
  @override
  State<_DocumentDialog> createState() => _DocumentDialogState();
}

class _DocumentDialogState extends State<_DocumentDialog> {
  late final TextEditingController title;
  late final TextEditingController body;
  late String kind;
  late final String _id;
  SourceDocument? _baseline;
  bool _saving = false;
  String? _pendingSave;
  String? _validationError;
  WorkspaceController get controller => widget.controller;
  bool get _locked => _saving || _pendingSave != null;
  SourceDocument? get _currentDocument => controller.workspace?.documents
      .where((document) => document.id == _id)
      .firstOrNull;
  bool get _hasConflict {
    final current = _currentDocument;
    final baseline = _baseline;
    if (current == null || baseline == null) return current != baseline;
    return current.title != baseline.title ||
        current.kind != baseline.kind ||
        current.body != baseline.body;
  }

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.document?.title ?? '新资料');
    body = TextEditingController(text: widget.document?.body ?? '');
    kind = widget.document?.kind ?? 'setting';
    _baseline = widget.document;
    _id =
        widget.document?.id ??
        'document-${DateTime.now().microsecondsSinceEpoch}';
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_pendingSave != null &&
        controller.lastConfirmedCommand?.requestId == _pendingSave) {
      _pendingSave = null;
      Navigator.pop(context);
    } else if (_pendingSave != null &&
        !controller.busy &&
        controller.pending == null) {
      setState(() => _pendingSave = null);
    }
  }

  Future<void> _save() async {
    if (controller.busy ||
        controller.pending != null ||
        _saving ||
        _hasConflict) {
      return;
    }
    if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
      setState(() => _validationError = '标题和内容不能为空。');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    final saved = await controller.act('saveDocument', {
      'id': _id,
      'title': title.text.trim(),
      'kind': kind,
      'body': body.text,
    });
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _pendingSave = controller.pending?.requestId;
      });
    }
  }

  void _loadLatest() {
    final current = _currentDocument;
    if (current == null ||
        controller.busy ||
        controller.pending != null ||
        _locked) {
      return;
    }
    setState(() {
      _baseline = current;
      title.text = current.title;
      body.text = current.body;
      kind = current.kind;
      _validationError = null;
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !_saving && !controller.busy,
      child: AlertDialog(
        title: const Text('知识库资料'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  readOnly: _locked,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: '资料身份'),
                  items: [
                    for (final k in ['setting', 'reference', 'plan'])
                      DropdownMenuItem(value: k, child: Text(_kind(k))),
                  ],
                  onChanged: _locked ? null : (v) => setState(() => kind = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: body,
                  readOnly: _locked,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    helperText: '参考资料请写明来源。',
                  ),
                ),
                if (_hasConflict) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('服务端资料已变化，当前草稿已保留。请查看新版资料后再决定。'),
                  ),
                  if (_currentDocument case final latest?)
                    ExpansionTile(
                      title: const Text('查看新版资料'),
                      children: [
                        Text('新版标题：${latest.title}'),
                        Text('新版身份：${_kind(latest.kind)}'),
                        SelectableText(latest.body),
                      ],
                    ),
                ],
                if (_validationError != null || controller.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_validationError ?? controller.error!),
                  ),
                if (controller.pending != null)
                  const Text('上次操作的结果尚未确认，输入已保留。请刷新或重试。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving || controller.busy
                ? null
                : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (controller.error != null ||
              controller.pending != null ||
              _hasConflict)
            TextButton(
              onPressed: controller.busy ? null : controller.load,
              child: const Text('刷新作品'),
            ),
          if (controller.pending != null)
            TextButton(
              onPressed: controller.busy ? null : controller.retry,
              child: const Text('重试上次操作'),
            ),
          if (_hasConflict && _currentDocument != null)
            TextButton(
              onPressed:
                  controller.busy || controller.pending != null || _locked
                  ? null
                  : _loadLatest,
              child: const Text('放弃草稿并加载新版资料'),
            ),
          FilledButton(
            onPressed:
                controller.busy ||
                    controller.pending != null ||
                    _saving ||
                    _hasConflict
                ? null
                : _save,
            child: const Text('保存资料'),
          ),
        ],
      ),
    ),
  );
}
