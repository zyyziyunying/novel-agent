import 'package:genkit/genkit.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:schemantic/schemantic.dart';

import 'library_service.dart';

class LibraryRuntime {
  LibraryRuntime(Genkit ai, LibraryService service) {
    action = ai.defineFlow<LibraryCommand, Json, void, void>(
      name: 'libraryAction',
      inputSchema: SchemanticType.from<LibraryCommand>(
        jsonSchema: {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'apiVersion': {'type': 'integer', 'const': 2},
            'requestId': {'type': 'string', 'minLength': 1},
            'expectedRevision': {'type': 'integer', 'minimum': 0},
            'target': {'type': 'object'},
            'operation': {'type': 'string'},
            'payload': {'type': 'object'},
          },
          'required': [
            'apiVersion',
            'requestId',
            'expectedRevision',
            'target',
            'operation',
            'payload',
          ],
        },
        parse: LibraryCommand.fromJson,
      ),
      outputSchema: SchemanticType.from<Json>(
        jsonSchema: {'type': 'object'},
        parse: (value) => value as Json,
      ),
      fn: (command, _) async {
        try {
          return await service.execute(command);
        } on LibraryFailure catch (failure) {
          throw GenkitException(
            failure.message,
            status: failure.code.contains('conflict')
                ? StatusCode.aborted
                : StatusCode.failedPrecondition,
            details: failure.code,
          );
        } on Object {
          throw GenkitException(
            '无法确认保存结果，请读取工作区后用同一请求重试。',
            status: StatusCode.internal,
          );
        }
      },
    );
  }
  late final Flow<LibraryCommand, Json, void, void> action;
}
