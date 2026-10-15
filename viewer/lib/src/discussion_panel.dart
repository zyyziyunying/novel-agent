import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'discussion_dialogs.dart';
import 'knowledge_details.dart';
import 'knowledge_metadata.dart';
import 'library_controller.dart';

class DiscussionPanel extends StatefulWidget {
  const DiscussionPanel({
    super.key,
    required this.controller,
    required this.workId,
  });
  final LibraryController controller;
  final String workId;
  @override
  State<DiscussionPanel> createState() => _DiscussionPanelState();
}

class _DiscussionPanelState extends State<DiscussionPanel> {
  final Map<String, TextEditingController> _inputs = {};
  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.controller;
    final work = catalog.workspace!.work(widget.workId);
    final selected = catalog.selectedDiscussion(work.id);
    final state = selected == null
        ? null
        : catalog.discussionState(work.id, selected.id);
    final input = selected == null
        ? null
        : _inputs.putIfAbsent(selected.id, TextEditingController.new);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey((work.id, selected?.id)),
                  initialValue: selected?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '持续讨论'),
                  hint: const Text('尚无讨论'),
                  items: [
                    for (final d in work.discussions)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(d.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) catalog.selectDiscussion(work.id, id);
                  },
                ),
              ),
              IconButton(
                tooltip: '新建讨论',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: catalog.canChangeCatalog
                    ? () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => NewDiscussionDialog(
                          controller: catalog,
                          workId: work.id,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        if (selected == null)
          const Expanded(child: Center(child: Text('新建作品或章节讨论，保存构思、审稿与改稿建议。')))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              selected.chapterId == null
                  ? '作品讨论 · 未采用的想法不会改变正文或记忆。'
                  : '章节讨论：${work.chapters.firstWhere((c) => c.id == selected.chapterId).title} · 建议需作者选择采用。',
            ),
          ),
          if (state!.busy) const LinearProgressIndicator(),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(state.error!),
            ),
          if (state.pending != null)
            Wrap(
              children: [
                const Text('本轮结果待确认。'),
                TextButton(
                  onPressed: state.busy ? null : catalog.load,
                  child: const Text('刷新讨论'),
                ),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => catalog.retryDiscussion(
                          work.id,
                          selected.id,
                          state.pending!.requestId,
                        ),
                  child: const Text('重试原请求'),
                ),
              ],
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (var i = 0; i < selected.turns.length; i++)
                  _turn(
                    context,
                    catalog,
                    work,
                    selected,
                    selected.turns[i],
                    i + 1,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('discussion-input'),
                  controller: input,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '讨论内容',
                    hintText: '描述想讨论的构思、审稿或改稿问题',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed:
                        state.busy ||
                            catalog.busy ||
                            catalog.hasPending ||
                            !catalog.modelAvailable
                        ? null
                        : () async {
                            final body = input!.text;
                            if (body.trim().isEmpty) return;
                            final completed = await catalog.sendDiscussion(
                              work.id,
                              selected.id,
                              body,
                            );
                            if (mounted && completed && input.text == body) {
                              input.clear();
                            }
                          },
                    child: const Text('发送新一轮'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _turn(
    BuildContext context,
    LibraryController catalog,
    NovelWork work,
    Discussion discussion,
    DiscussionTurn turn,
    int number,
  ) {
    final state = catalog.discussionState(work.id, discussion.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 $number 轮 · ${switch (turn.status) {
                'completed' => '已完成',
                'pending' => '等待回复',
                _ => '未完成',
              }}',
            ),
            for (final messageId in [
              turn.authorMessageId,
              ?turn.assistantMessageId,
            ])
              _message(
                context,
                catalog,
                work.id,
                discussion.id,
                discussion.messages.firstWhere((m) => m.id == messageId),
              ),
            if (turn.status == 'failed')
              Text(discussionFailure(turn.errorCode)),
            if (turn.status != 'completed' &&
                discussion.turns.last.requestId == turn.requestId)
              Wrap(
                children: [
                  TextButton(
                    onPressed:
                        catalog.busy ||
                            state.busy ||
                            (catalog.hasPending &&
                                state.pending?.requestId != turn.requestId)
                        ? null
                        : () => catalog.retryDiscussion(
                            work.id,
                            discussion.id,
                            turn.requestId,
                          ),
                    child: const Text('重试本轮'),
                  ),
                  TextButton(
                    onPressed: catalog.busy ? null : catalog.load,
                    child: const Text('刷新讨论'),
                  ),
                ],
              ),
            ExpansionTile(
              title: const Text('查看本轮引用与版本'),
              children: [
                for (final entry in turn.basis.chapterHeads.entries)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      _chapterSource(work, entry.key, entry.value),
                    ),
                  ),
                if (turn.basis.documents.isEmpty) const Text('本轮没有采用资料。'),
                if (turn.readDocuments != null)
                  KnowledgeReadSummary(
                    catalog: knowledgeCatalog(catalog.workspace!, turn.basis),
                    readDocuments: turn.readDocuments!,
                  ),
                for (final ref in turn.readDocuments ?? turn.basis.documents)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          '知识库：${catalog.workspace!.library(ref.libraryId).name} · 资料 ID：${ref.documentId}',
                        ),
                        KnowledgeDetails(
                          version: catalog.workspace!.documentVersion(ref),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _chapterSource(NovelWork work, String chapterId, String versionId) {
    final chapter = work.chapters.firstWhere((c) => c.id == chapterId);
    final number = chapter.versions.indexWhere((v) => v.id == versionId) + 1;
    return '正文：第 ${chapter.number} 章 · ${chapter.title} · 第 $number 版';
  }

  Widget _message(
    BuildContext context,
    LibraryController catalog,
    String workId,
    String discussionId,
    DiscussionMessage message,
  ) {
    final source = DiscussionSource(
      workId: workId,
      discussionId: discussionId,
      messageId: message.id,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(message.role == 'author' ? '作者' : '助手 · ${message.provider}'),
        SelectableText(message.body),
        Wrap(
          children: [
            TextButton(
              onPressed:
                  catalog.canChangeCatalog &&
                      catalog.workspace!.libraries.isNotEmpty
                  ? () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => AdoptDiscussionDialog(
                        controller: catalog,
                        source: source,
                        edit: false,
                      ),
                    )
                  : null,
              child: const Text('保存到知识库'),
            ),
            TextButton(
              onPressed:
                  catalog.canChangeCatalog &&
                      catalog.workspace!
                          .work(workId)
                          .chapters
                          .any((c) => c.body.isNotEmpty)
                  ? () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => AdoptDiscussionDialog(
                        controller: catalog,
                        source: source,
                        edit: true,
                      ),
                    )
                  : null,
              child: const Text('生成改稿提案'),
            ),
          ],
        ),
      ],
    );
  }
}
