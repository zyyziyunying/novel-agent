import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';

class HangingModel extends FixtureNovelModel {
  @override
  Future<String> discuss(Json context, String instruction) {
    stdout.writeln('pending-saved');
    return Completer<String>().future;
  }
}

Future<void> main(List<String> args) async {
  final repository = await FileLibraryRepository.open(args[0]);
  final service = LibraryService(repository, model: HangingModel());
  final command = LibraryCommand.fromJson(
    jsonDecode(await File(args[1]).readAsString()),
  );
  unawaited(service.execute(command));
  // Keep the worker alive until the test kills the process after the pending commit.
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
