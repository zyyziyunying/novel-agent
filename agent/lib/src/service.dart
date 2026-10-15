import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:novel_contracts/novel_contracts.dart';

import 'model.dart';
import 'knowledge_reader.dart';
import 'repository.dart';

class NovelFailure implements Exception {
  const NovelFailure(this.code, this.message);
  final String code;
  final String message;
}

class NovelService {
  NovelService(this.repository, this.model, {this.contextMetadata = const {}});
  final WorkspaceRepository repository;
  final NovelModel? model;
  final Json contextMetadata;
  Future<void> _tail = Future.value();
  final Map<String, (String, Future<Json>)> _inFlight = {};

  Future<T> _locked<T>(Future<T> Function() work) {
    final future = _tail.then((_) => work());
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  Future<Json> snapshot() async => _result(await repository.load());
  Json _result(Workspace workspace, {bool reused = false}) => {
    'workspace': workspace.toJson(),
    'provider': model?.name,
    'reused': reused,
  };

  Future<Json> execute(NovelCommand command) {
    final fingerprint = sha256
        .convert(utf8.encode(command.canonical))
        .toString();
    final pending = _inFlight[command.requestId];
    if (pending != null) {
      if (pending.$1 != fingerprint) {
        return Future.error(
          const NovelFailure('request_conflict', '同一个请求编号不能用于不同操作。'),
        );
      }
      return pending.$2;
    }
    final future = _execute(command, fingerprint);
    _inFlight[command.requestId] = (fingerprint, future);
    // Attach cleanup without creating an unhandled error future.
    unawaited(
      future.then<void>(
        (_) {
          _inFlight.remove(command.requestId);
        },
        onError: (Object _) {
          _inFlight.remove(command.requestId);
        },
      ),
    );
    return future;
  }

  bool _reused(Workspace workspace, NovelCommand command, String fingerprint) {
    final receipt = workspace.receipts[command.requestId];
    if (receipt == null) return false;
    if (receipt.fingerprint != fingerprint) {
      throw const NovelFailure('request_conflict', '同一个请求编号不能用于不同操作。');
    }
    return true;
  }

  Future<Json> _execute(NovelCommand command, String fingerprint) async {
    final base = await _locked(repository.load);
    if (_reused(base, command, fingerprint)) return _result(base, reused: true);
    if (base.revision != command.expectedRevision) {
      throw const NovelFailure('version_conflict', '作品已发生变化，请刷新后重新操作。');
    }
    final payload = command.payload;
    Workspace next;
    switch (command.operation) {
      case 'createChapter':
        if (base.chapters.any((c) => c.id == payload['chapterId'])) {
          throw const NovelFailure('chapter_exists', '章节编号已存在。');
        }
        final version = TextVersion(
          id: 'version-${base.revision + 1}',
          body: '',
        );
        next = base.replace(
          chapters: [
            ...base.chapters,
            Chapter(
              id: payload['chapterId'],
              number: base.chapters.length + 1,
              title: payload['title'],
              head: version.id,
              versions: [version],
            ),
          ],
        );
      case 'proposeChapter':
      case 'proposeEdit':
        final edit = command.operation == 'proposeEdit';
        if (!edit && base.chapters.any((c) => c.body.trim().isEmpty)) {
          throw const NovelFailure('chapter_empty', '请先填写并保存空白章节，再起草下一章。');
        }
        if (!edit && !base.memoryFresh) {
          throw const NovelFailure('memory_stale', '记忆已失效，请先重建记忆再续写。');
        }
        if (!edit && base.chapters.any((c) => c.needsReview)) {
          throw const NovelFailure('review_required', '请先复查受旧章修改影响的章节。');
        }
        final context = writingContext(base);
        context.addAll(contextMetadata);
        context['authorInstruction'] = payload['instruction'];
        Chapter? target;
        if (edit) {
          target = _chapter(base, payload['chapterId']);
          final start = payload['start'] as int;
          final end = payload['end'] as int;
          if (start >= end ||
              end > target.body.length ||
              !_boundary(target.body, start) ||
              !_boundary(target.body, end)) {
            throw const NovelFailure('invalid_selection', '请选择正文中的完整文本范围。');
          }
          context['selection'] = {
            'chapterId': target.id,
            'versionId': target.head,
            'start': start,
            'end': end,
            'text': target.body.substring(start, end),
          };
        }
        late PreparedKnowledge prepared;
        final draft = await _modelCall(
          () => (() async {
            prepared = await prepareKnowledge(
              model!,
              context,
              payload['instruction'],
              task: edit ? '改写选段' : '起草下一章',
            );
            return model!.write(
              prepared.context,
              payload['instruction'],
              edit: edit,
            );
          })().timeout(const Duration(seconds: 90)),
        );
        if (draft.body.trim().isEmpty || draft.body.length > 100000) {
          throw const NovelFailure('invalid_output', '模型正文为空或超过原型限制。');
        }
        final body = edit
            ? target!.body.replaceRange(
                payload['start'],
                payload['end'],
                draft.body,
              )
            : draft.body;
        if (body.length > 100000) {
          throw const NovelFailure('invalid_output', '改写后的整章超过原型限制，提案未保存。');
        }
        final proposal = Proposal(
          id: 'proposal-${base.revision + 1}',
          chapterId: target?.id ?? _nextChapterId(base),
          title: target?.title ?? draft.title,
          body: body,
          baseHeads: base.currentHeads,
          baseRevision: base.revision,
          status: 'pending',
          provider: model!.name,
          context: prepared.context,
          usage: {
            ...draft.usage,
            if (prepared.usage.isNotEmpty) 'knowledgeSelection': prepared.usage,
          },
        );
        next = base.replace(proposals: [...base.proposals, proposal]);
      case 'acceptProposal':
      case 'rejectProposal':
        final proposal = base.proposals
            .where((p) => p.id == payload['proposalId'])
            .firstOrNull;
        if (proposal == null || proposal.status != 'pending') {
          throw const NovelFailure('proposal_unavailable', '这个提案已处理或不存在。');
        }
        final accept = command.operation == 'acceptProposal';
        if (accept &&
            (!sameHeads(proposal.baseHeads, base.currentHeads) ||
                (proposal.context.containsKey('knowledgeCatalog')
                    ? jsonEncode(proposal.context['knowledgeCatalog']) !=
                          jsonEncode(catalogFromContext(contextMetadata))
                    : jsonEncode(proposal.context['documents']) !=
                          jsonEncode(
                            base.documents.map((d) => d.toJson()).toList(),
                          )))) {
          throw const NovelFailure('version_conflict', '提案所依据的正文或资料已改变，请重新生成。');
        }
        next = base.replace(
          proposals: [
            for (final p in base.proposals)
              p.id == proposal.id
                  ? p.decide(accept ? 'accepted' : 'rejected')
                  : p,
          ],
        );
        if (accept) {
          final chapter = base.chapters
              .where((c) => c.id == proposal.chapterId)
              .firstOrNull;
          if (chapter == null) {
            final version = TextVersion(
              id: 'version-${base.revision + 1}',
              body: proposal.body,
            );
            next = next.replace(
              chapters: [
                ...base.chapters,
                Chapter(
                  id: proposal.chapterId,
                  number: base.chapters.length + 1,
                  title: proposal.title,
                  head: version.id,
                  versions: [version],
                ),
              ],
            );
          } else {
            next = _saveBody(next, chapter, proposal.body);
          }
        }
      case 'saveChapter':
        next = _saveBody(
          base,
          _chapter(base, payload['chapterId']),
          payload['body'],
        );
      case 'restoreVersion':
        final chapter = _chapter(base, payload['chapterId']);
        final versionId = payload['versionId'];
        if (!chapter.versions.any((v) => v.id == versionId)) {
          throw const NovelFailure('version_missing', '所选历史版本不存在。');
        }
        next = base.replace(
          chapters: [
            for (final c in base.chapters)
              if (c.id == chapter.id)
                c.replace(head: versionId, needsReview: false)
              else
                c.number > chapter.number ? c.replace(needsReview: true) : c,
          ],
        );
      case 'confirmReview':
        final chapter = _chapter(base, payload['chapterId']);
        next = base.replace(
          chapters: [
            for (final c in base.chapters)
              c.id == chapter.id ? c.replace(needsReview: false) : c,
          ],
        );
      case 'rebuildMemory':
        if (base.chapters.any((c) => c.body.trim().isEmpty)) {
          throw const NovelFailure('chapter_empty', '请先填写并保存空白章节，再重建记忆。');
        }
        final facts = await _modelCall(() => model!.extract(base));
        if (facts.length > base.chapters.length * 8 ||
            base.chapters.any(
              (c) =>
                  !facts.any((f) => f.chapterId == c.id) ||
                  facts.where((f) => f.chapterId == c.id).length > 8,
            )) {
          throw const NovelFailure('invalid_memory', '记忆未覆盖每章，或超过原型限制。');
        }
        try {
          next = base.replace(
            memories: [
              ...base.memories,
              MemorySnapshot(
                id: 'memory-${base.revision + 1}',
                sourceHeads: base.currentHeads,
                facts: facts,
              ),
            ],
          );
        } on FormatException {
          throw const NovelFailure('invalid_memory', '记忆证据不属于当前正文，重建未应用。');
        }
      case 'saveDocument':
        final document = SourceDocument.fromJson(payload);
        next = base.replace(
          documents: [
            for (final d in base.documents)
              if (d.id != document.id) d,
            document,
          ],
        );
      default:
        throw const NovelFailure('invalid_operation', '不支持的操作。');
    }
    return _locked(() async {
      final current = await repository.load();
      if (_reused(current, command, fingerprint)) {
        return _result(current, reused: true);
      }
      if (current.revision != base.revision) {
        throw const NovelFailure('version_conflict', '运行期间作品已改变，结果未应用，请重新操作。');
      }
      next = next.replace(
        revision: base.revision + 1,
        receipts: {
          ...base.receipts,
          command.requestId: Receipt(
            fingerprint: fingerprint,
            revision: base.revision + 1,
          ),
        },
      );
      try {
        await repository.save(next, base.revision);
      } on WorkspaceConflict {
        throw const NovelFailure('version_conflict', '作品已改变，结果未应用。');
      }
      return _result(next);
    });
  }

  static bool _boundary(String body, int index) =>
      index == 0 ||
      index == body.length ||
      !(body.codeUnitAt(index) >= 0xdc00 &&
          body.codeUnitAt(index) <= 0xdfff &&
          body.codeUnitAt(index - 1) >= 0xd800 &&
          body.codeUnitAt(index - 1) <= 0xdbff);

  Chapter _chapter(Workspace workspace, String id) {
    final chapter = workspace.chapters.where((c) => c.id == id).firstOrNull;
    if (chapter == null) throw const NovelFailure('chapter_missing', '章节不存在。');
    return chapter;
  }

  String _nextChapterId(Workspace workspace) {
    var number = workspace.chapters.length + 1;
    while (workspace.chapters.any((c) => c.id == 'chapter-$number')) {
      number++;
    }
    return 'chapter-$number';
  }

  Workspace _saveBody(Workspace base, Chapter chapter, String body) {
    if (body.trim().isEmpty || body.length > 100000) {
      throw const NovelFailure(
        'invalid_body',
        '正文不能为空，且不得超过 100000 个 UTF-16 单元。',
      );
    }
    if (body == chapter.body) return base;
    final version = TextVersion(id: 'version-${base.revision + 1}', body: body);
    return base.replace(
      chapters: [
        for (final c in base.chapters)
          if (c.id == chapter.id)
            c.replace(
              head: version.id,
              versions: [...c.versions, version],
              needsReview: false,
            )
          else
            c.number > chapter.number ? c.replace(needsReview: true) : c,
      ],
    );
  }

  Future<T> _modelCall<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on Object {
      throw const NovelFailure('model_failed', '模型调用失败或输出无效；原文未改变，请重试。');
    }
  }
}
