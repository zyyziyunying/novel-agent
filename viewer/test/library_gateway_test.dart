import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';
import 'package:novel_workbench/src/library_gateway.dart';

void main() {
  test('格式 2 网关读取空目录、无模型状态，发送目录目标与 Genkit envelope', () async {
    final workspace = LibraryWorkspace(
      revision: 0,
      works: [],
      libraries: [],
      receipts: {},
    );
    final command = LibraryCommand(
      requestId: 'create',
      expectedRevision: 0,
      target: CommandTarget.catalog(),
      operation: 'createWork',
      payload: {'id': 'work-a', 'title': '航海记'},
    );
    final gateway = HttpLibraryGateway(
      endpoint: Uri.parse('http://127.0.0.1:4100'),
      token: 'session',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer session');
        final result = {
          'workspace': workspace.toJson(),
          'provider': null,
          'modelAvailable': false,
          'reused': false,
        };
        if (request.method == 'POST') {
          expect(request.url.path, '/libraryAction');
          expect(jsonDecode(request.body), {'data': command.toJson()});
        } else {
          expect(request.url.path, '/libraryWorkspace');
        }
        return http.Response(
          jsonEncode(request.method == 'POST' ? {'result': result} : result),
          200,
        );
      }),
    );
    addTearDown(gateway.close);
    expect((await gateway.load()).modelAvailable, isFalse);
    expect((await gateway.execute(command)).provider, isNull);
  });

  for (final status in [409, 500]) {
    test('HTTP $status 正确区分确定冲突和待确认请求', () async {
      final gateway = HttpLibraryGateway(
        endpoint: Uri.parse('http://127.0.0.1:4100'),
        token: 'session',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'message': '目标 A 操作失败'}),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(gateway.close);
      await expectLater(
        gateway.execute(
          LibraryCommand(
            requestId: 'save',
            expectedRevision: 0,
            target: CommandTarget.work('work-a'),
            operation: 'rebuildMemory',
            payload: {},
          ),
        ),
        throwsA(
          isA<GatewayFailure>()
              .having((f) => f.message, 'message', '目标 A 操作失败')
              .having((f) => f.uncertain, 'uncertain', status == 500),
        ),
      );
    });
  }
}
