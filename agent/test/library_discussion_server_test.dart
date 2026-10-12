import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

import 'support/library_commands.dart';
import 'support/library_server.dart';

void main() {
  test(
    'HTTP 三轮讨论、强制重启、无模型回看和成果保存，重复请求不重复采用',
    () async {
      final dir = await Directory.systemTemp.createTemp('novel-m5-http-');
      addTearDown(() => dir.delete(recursive: true));
      var server = await LibraryAgentProcess.start(dir, fixture: true);
      addTearDown(() => server.stop());
      var revision = 0;
      Future<Json> act(LibraryCommand c) async {
        final result = await server.execute(c);
        revision = result['workspace']['revision'];
        return result;
      }

      await act(createWork(revision));
      await act(createWork(revision, 'work-b'));
      await act(createLibrary(revision));
      for (final workId in ['work-a', 'work-b']) {
        await act(
          command(
            'talk-$workId',
            revision,
            'createDiscussion',
            {'id': 'talk', 'title': '持续讨论', 'chapterId': null},
            target: CommandTarget.work(workId),
          ),
        );
      }
      late LibraryCommand original;
      for (var i = 1; i <= 3; i++) {
        original = command(
          'round-$i',
          revision,
          'sendDiscussionMessage',
          {'messageId': 'author-$i', 'body': '第 $i 轮构思'},
          target: CommandTarget.discussion(
            workId: 'work-a',
            discussionId: 'talk',
          ),
        );
        await act(original);
      }
      final before = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      final talk = before.work('work-a').discussions.single;
      expect(talk.messages.length, 6);
      expect(talk.turns.every((t) => t.status == 'completed'), isTrue);
      expect(before.work('work-b').discussions.single.messages, isEmpty);
      expect(before.work('work-a').chapters, isEmpty);
      expect(before.work('work-a').memories, isEmpty);
      await server.stop(abrupt: true);
      server = await LibraryAgentProcess.start(dir);
      final loaded = (await server.request('/libraryWorkspace')).$2;
      expect(loaded['modelAvailable'], isFalse);
      expect(loaded['workspace'], before.toJson());
      expect((await server.execute(original))['reused'], isTrue);
      final source = DiscussionSource(
        workId: 'work-a',
        discussionId: 'talk',
        messageId: talk.messages.last.id,
      );
      final version = KnowledgeVersion(
        id: 'from-talk-v1',
        title: '讨论选定计划',
        kind: 'plan',
        body: talk.messages.last.body,
        associatedWorkId: 'work-a',
        provenance: SourceProvenance(
          writer: SourceWriter(kind: 'author', id: 'author'),
          sources: [source],
        ),
      );
      final adopt = command(
        'adopt',
        revision,
        'adoptDiscussionMessage',
        {
          'source': source.toJson(),
          'documentId': 'plan',
          'expectedVersionId': null,
          'version': version.toJson(),
        },
        target: CommandTarget.library('library-a', workId: 'work-a'),
      );
      await act(adopt);
      expect((await server.execute(adopt))['reused'], isTrue);
      final conflict = await server.request(
        '/libraryAction',
        body: {
          'data': command('adopt', revision, 'adoptDiscussionMessage', {
            ...adopt.payload,
            'documentId': 'different',
          }, target: adopt.target).toJson(),
        },
      );
      expect(conflict.$1, 409);
      await server.stop(abrupt: true);
      server = await LibraryAgentProcess.start(dir);
      final after = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      expect(
        after.library('library-a').documents.single.current.toJson(),
        version.toJson(),
      );
      expect(after.work('work-a').knowledgeLinks, isEmpty);
      expect(after.work('work-a').discussions.single.toJson(), talk.toJson());
      expect(after.work('work-b').discussions.single.messages, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 50)),
  );

  test(
    '模型调用中 SIGKILL，启动标记 interrupted，显式原请求重试只产生一条回复',
    () async {
      final dir = await Directory.systemTemp.createTemp('novel-m5-crash-');
      addTearDown(() => dir.delete(recursive: true));
      var server = await LibraryAgentProcess.start(dir);
      addTearDown(() => server.stop());
      await server.execute(createWork());
      await server.execute(
        command('talk', 1, 'createDiscussion', {
          'id': 'talk',
          'title': '中断讨论',
          'chapterId': null,
        }, target: CommandTarget.work('work-a')),
      );
      await server.stop();
      final original = command(
        'crash-round',
        2,
        'sendDiscussionMessage',
        {'messageId': 'author', 'body': '崩溃前的原始要求'},
        target: CommandTarget.discussion(
          workId: 'work-a',
          discussionId: 'talk',
        ),
      );
      final commandFile = File('${dir.path}/request.json');
      await commandFile.writeAsString(jsonEncode(original.toJson()));
      final library = (await Isolate.resolvePackageUri(
        Uri.parse('package:novel_agent/novel_agent.dart'),
      ))!;
      final workerPath = File.fromUri(library).parent.parent.uri
          .resolve('test/support/crash_discussion.dart')
          .toFilePath();
      final config = (await Isolate.packageConfig)!.toFilePath();
      final worker = await Process.start(Platform.resolvedExecutable, [
        '--disable-dart-dev',
        '--packages=$config',
        workerPath,
        '${dir.path}/data/library-workspace.json',
        commandFile.path,
      ]);
      addTearDown(() {
        worker.kill(ProcessSignal.sigkill);
      });
      worker.stderr.transform(utf8.decoder).listen((line) {});
      await worker.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'pending-saved')
          .timeout(const Duration(seconds: 10));
      final pending = LibraryWorkspace.fromJson(
        jsonDecode(
          await File('${dir.path}/data/library-workspace.json').readAsString(),
        ),
      );
      expect(
        pending.work('work-a').discussions.single.turns.single.status,
        'pending',
      );
      worker.kill(ProcessSignal.sigkill);
      await worker.exitCode;
      server = await LibraryAgentProcess.start(dir, fixture: true);
      final interrupted = LibraryWorkspace.fromJson(
        (await server.request('/libraryWorkspace')).$2['workspace'],
      );
      expect(
        interrupted.work('work-a').discussions.single.turns.single.errorCode,
        'interrupted',
      );
      expect(interrupted.work('work-a').discussions.single.messages.length, 1);
      final result = await server.execute(original);
      final completed = LibraryWorkspace.fromJson(result['workspace']);
      final discussion = completed.work('work-a').discussions.single;
      expect(discussion.turns.single.status, 'completed');
      expect(discussion.messages.length, 2);
      expect(
        discussion.turns.single.basis.toJson(),
        pending.work('work-a').discussions.single.turns.single.basis.toJson(),
      );
      expect(discussion.messages.first.body, '崩溃前的原始要求');
      final savedRevision = completed.revision;
      expect((await server.execute(original))['reused'], isTrue);
      expect(
        (await server.request('/libraryWorkspace')).$2['workspace']['revision'],
        savedRevision,
      );
    },
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
