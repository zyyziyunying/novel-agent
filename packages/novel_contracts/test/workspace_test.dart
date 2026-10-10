import 'dart:convert';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('工作区冷加载保留正文、版本与记忆来源', () {
    final original = demoWorkspace();
    final loaded = Workspace.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );
    expect(loaded.chapters.first.body, original.chapters.first.body);
    expect(loaded.memoryFresh, isTrue);
    expect(loaded.currentMemory!.facts.first.versionId, 'seed-1');
  });
  test('未知字段、格式版本和非整数修订号被拒绝', () {
    expect(
      () => Workspace.fromJson({...demoWorkspace().toJson(), 'unknown': true}),
      throwsFormatException,
    );
    expect(
      () =>
          Workspace.fromJson({...demoWorkspace().toJson(), 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => NovelCommand.fromJson({
        'requestId': 'r',
        'expectedRevision': 1.0,
        'operation': 'rebuildMemory',
        'payload': {},
      }),
      throwsFormatException,
    );
  });
  test('记忆证据必须属于来源版本的原文', () {
    final workspace = demoWorkspace();
    expect(
      () => workspace.replace(
        memories: [
          MemorySnapshot(
            id: 'bad',
            sourceHeads: workspace.currentHeads,
            facts: const [
              StoryFact(
                text: '推断',
                chapterId: 'chapter-1',
                versionId: 'seed-1',
                evidence: '原文没有这句话',
              ),
            ],
          ),
        ],
      ),
      throwsFormatException,
    );
  });
}
