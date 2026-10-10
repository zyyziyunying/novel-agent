import 'package:genkit/genkit.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:schemantic/schemantic.dart';

import 'service.dart';

class NovelRuntime {
  NovelRuntime(Genkit ai, NovelService service) {
    action = ai.defineFlow<NovelCommand, Json, void, void>(
      name: 'novelAction',
      inputSchema: SchemanticType.from<NovelCommand>(
        jsonSchema: {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'requestId': {'type': 'string', 'minLength': 1},
            'expectedRevision': {'type': 'integer', 'minimum': 0},
            'operation': {'type': 'string'},
            'payload': {'type': 'object'},
          },
          'required': ['requestId', 'expectedRevision', 'operation', 'payload'],
        },
        parse: NovelCommand.fromJson,
      ),
      outputSchema: SchemanticType.from<Json>(
        jsonSchema: {'type': 'object'},
        parse: (v) => v as Json,
      ),
      fn: (command, _) async {
        try {
          return await service.execute(command);
        } on NovelFailure catch (failure) {
          throw GenkitException(
            failure.message,
            status: failure.code.contains('conflict')
                ? StatusCode.aborted
                : StatusCode.failedPrecondition,
            details: failure.code,
          );
        } on Object {
          throw GenkitException(
            '无法保存作品，操作未确认完成。请刷新检查后用同一请求重试。',
            status: StatusCode.internal,
          );
        }
      },
    );
  }
  late final Flow<NovelCommand, Json, void, void> action;
}
