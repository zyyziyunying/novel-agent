import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

List<String> knowledgeTags(String text) => text
    .split(RegExp(r'[,，\n]'))
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toSet()
    .toList();

class KnowledgeMetadataEditor extends StatelessWidget {
  const KnowledgeMetadataEditor({
    super.key,
    required this.description,
    required this.tags,
    required this.alwaysRead,
    required this.editable,
    required this.onAlwaysReadChanged,
  });
  final TextEditingController description;
  final TextEditingController tags;
  final bool alwaysRead;
  final bool editable;
  final ValueChanged<bool> onAlwaysReadChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: ValueKey(('description', editable)),
        controller: description,
        readOnly: !editable,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: '资料简介（description）',
          helperText: '说明包含什么、何时需要读。留空时会读取全文。',
          helperMaxLines: 3,
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: ValueKey(('tags', editable)),
        controller: tags,
        readOnly: !editable,
        decoration: const InputDecoration(
          labelText: '标签（TAG）',
          helperText: '用逗号分隔，最多 20 个，每个最多 40 字符。',
          helperMaxLines: 3,
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('必读资料'),
        subtitle: const Text('作品采用此版本后，每次写作和讨论都会读取全文。'),
        value: alwaysRead,
        onChanged: editable ? onAlwaysReadChanged : null,
      ),
    ],
  );
}

class KnowledgeMetadata extends StatelessWidget {
  const KnowledgeMetadata({super.key, required this.version});
  final KnowledgeVersion version;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (version.description.trim().isNotEmpty)
        Text('简介：${version.description}'),
      if (version.tags.isNotEmpty)
        Wrap(
          spacing: 6,
          children: [for (final tag in version.tags) Chip(label: Text(tag))],
        ),
      Text(
        version.alwaysRead
            ? '必读资料'
            : version.requiresFullText
            ? '未填写简介，暂按全文读取'
            : '按需读取正文',
      ),
    ],
  );
}

class KnowledgeReadSummary extends StatelessWidget {
  const KnowledgeReadSummary({
    super.key,
    required this.catalog,
    required this.readDocuments,
  });
  final List catalog;
  final List<DocumentReference> readDocuments;
  @override
  Widget build(BuildContext context) {
    final read = readDocuments.map(knowledgeKey).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('资料目录 ${catalog.length} 份 · 本次加载全文 ${read.length} 份'),
        for (final entry in catalog)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['title']} · ${read.contains(entry['key']) ? '已加载全文' : '仅看简介'}'
                  '${entry['alwaysRead'] == true ? ' · 必读' : ''}',
                ),
                SelectableText(
                  '知识库 ID：${entry['libraryId']} · 资料 ID：${entry['documentId']} · 版本 ID：${entry['versionId']}',
                ),
                Text(
                  '简介：${(entry['description'] as String).trim().isEmpty ? '未填写，按全文读取' : entry['description']}',
                ),
                if ((entry['tags'] as List).isNotEmpty)
                  Text('标签：${(entry['tags'] as List).join('、')}'),
              ],
            ),
          ),
      ],
    );
  }
}
