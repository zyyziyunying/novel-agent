import 'dart:async';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_gateway.dart';

NovelWork testWork(String id, String title) {
  final demo = demoWorkspace();
  return NovelWork(
    id: id,
    title: title,
    knowledgeLinks: [],
    chapters: demo.chapters,
    proposals: [],
    memories: demo.memories,
    discussions: [],
  );
}

class FakeLibraryGateway implements LibraryGateway {
  LibraryWorkspace workspace = LibraryWorkspace(
    revision: 0,
    works: [testWork('work-a', '作品 A'), testWork('work-b', '作品 B')],
    libraries: [],
    receipts: {},
  );
  final List<LibraryCommand> commands = [];
  Completer<LibraryResult>? response;
  GatewayFailure? failure;
  bool commitBeforeFailure = false;
  bool modelAvailable = true;
  LibraryResult result() => LibraryResult(
    workspace,
    modelAvailable ? 'fixture/local' : null,
    modelAvailable,
  );
  @override
  Future<LibraryResult> load() async => result();
  @override
  Future<LibraryResult> execute(LibraryCommand command) async {
    commands.add(command);
    if (failure != null && !commitBeforeFailure) throw failure!;
    if (!workspace.receipts.containsKey(command.requestId)) {
      if (command.expectedRevision != workspace.revision) {
        throw const GatewayFailure('版本冲突');
      }
      var works = workspace.works;
      var libraries = workspace.libraries;
      if (command.operation == 'createWork') {
        works = [
          ...works,
          NovelWork(
            id: command.payload['id'],
            title: command.payload['title'],
            knowledgeLinks: [],
            chapters: [],
            proposals: [],
            memories: [],
            discussions: [],
          ),
        ];
      } else if (command.operation == 'createLibrary') {
        libraries = [
          ...libraries,
          KnowledgeLibrary(
            id: command.payload['id'],
            name: command.payload['name'],
            documents: [],
          ),
        ];
      } else if (command.operation == 'renameLibrary' ||
          command.operation == 'saveDocument') {
        final library = workspace.library(command.target.libraryId!);
        var documents = library.documents;
        if (command.operation == 'saveDocument') {
          final document = documents
              .where((d) => d.id == command.payload['documentId'])
              .firstOrNull;
          if (document?.head != command.payload['expectedVersionId']) {
            throw const GatewayFailure('资料版本冲突');
          }
          final version = KnowledgeVersion.fromJson(command.payload['version']);
          documents = [
            for (final d in documents)
              if (d.id != command.payload['documentId']) d,
            KnowledgeDocument(
              id: command.payload['documentId'],
              head: version.id,
              versions: [...?document?.versions, version],
            ),
          ];
        }
        libraries = [
          for (final l in libraries)
            if (l.id == library.id)
              KnowledgeLibrary(
                id: l.id,
                name: command.operation == 'renameLibrary'
                    ? command.payload['name']
                    : l.name,
                documents: documents,
              )
            else
              l,
        ];
      } else {
        final work = workspace.work(command.target.workId!);
        var chapters = work.chapters;
        var proposals = work.proposals;
        if (command.operation == 'createChapter') {
          final version = TextVersion(
            id: 'v-${workspace.revision + 1}',
            body: '',
          );
          chapters = [
            ...chapters,
            Chapter(
              id: command.payload['chapterId'],
              number: chapters.length + 1,
              title: command.payload['title'],
              head: version.id,
              versions: [version],
            ),
          ];
        }
        if (command.operation == 'saveChapter') {
          chapters = [
            for (final c in chapters)
              if (c.id == command.payload['chapterId'])
                c.replace(
                  head: 'v-${workspace.revision + 1}',
                  versions: [
                    ...c.versions,
                    TextVersion(
                      id: 'v-${workspace.revision + 1}',
                      body: command.payload['body'],
                    ),
                  ],
                )
              else
                c,
          ];
        }
        if (command.operation == 'proposeChapter') {
          proposals = [
            ...proposals,
            WorkProposal(
              workId: work.id,
              documents: [],
              discussionSource: null,
              proposal: Proposal(
                id: 'p-${workspace.revision + 1}',
                chapterId: 'chapter-3',
                title: '${work.title} 的提案',
                body: '新提案正文',
                baseHeads: work.currentHeads,
                baseRevision: workspace.revision,
                status: 'pending',
                provider: 'fixture/local',
                context: {
                  'documents': [],
                  'authorInstruction': command.payload['instruction'],
                },
                usage: {},
              ),
            ),
          ];
        }
        final replacement = NovelWork(
          id: work.id,
          title: command.operation == 'renameWork'
              ? command.payload['title']
              : work.title,
          knowledgeLinks: command.operation == 'setKnowledgeLinks'
              ? (command.payload['links'] as List)
                    .map(LibraryLink.fromJson)
                    .toList()
              : work.knowledgeLinks,
          chapters: chapters,
          proposals: proposals,
          memories: work.memories,
          discussions: work.discussions,
        );
        works = [for (final w in works) w.id == work.id ? replacement : w];
      }
      workspace = LibraryWorkspace(
        revision: workspace.revision + 1,
        works: works,
        libraries: libraries,
        receipts: {
          ...workspace.receipts,
          command.requestId: BoundReceipt(
            fingerprint: 'test',
            revision: workspace.revision + 1,
            target: command.target,
          ),
        },
      );
    }
    if (failure != null) throw failure!;
    return response == null ? result() : response!.future;
  }

  @override
  void close() {}
}
