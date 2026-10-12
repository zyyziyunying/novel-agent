import 'package:flutter/material.dart';
import 'package:novel_contracts/novel_contracts.dart';

String knowledgeKind(String kind) => switch (kind) {
  'setting' => '作者设定',
  'reference' => '外部参考',
  'plan' => '未来计划',
  _ => kind,
};

String knowledgeVersionLabel(KnowledgeDocument document, String id) =>
    '第 ${document.versions.indexWhere((v) => v.id == id) + 1} 版';

/// Displays the persisted original sources, including sources written by tools.
class KnowledgeDetails extends StatelessWidget {
  const KnowledgeDetails({super.key, required this.version});
  final KnowledgeVersion version;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${version.title}（${knowledgeKind(version.kind)}）'),
      SelectableText('版本 ID：${version.id}'),
      Text(
        '写入者：${version.provenance.writer.kind} / ${version.provenance.writer.id}',
      ),
      for (final source in version.provenance.sources)
        SelectableText(switch (source) {
          ExternalSource() => '原始来源（${source.kind}）：${source.reference}',
          DiscussionSource() =>
            '讨论来源：${source.workId} / ${source.discussionId} / ${source.messageId}',
        }),
      if (version.associatedWorkId != null)
        Text('来源关联作品：${version.associatedWorkId}'),
      const SizedBox(height: 12),
      SelectableText(version.body),
    ],
  );
}
