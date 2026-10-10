import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:novel_workbench/src/gateway.dart';

void main() {
  test('网关使用会话令牌、Genkit envelope 并解析工作区', () async {
    final gateway = HttpNovelGateway(
      endpoint: Uri.parse('http://127.0.0.1:4100'),
      token: 'session',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer session');
        expect(jsonDecode(request.body)['data']['operation'], 'rebuildMemory');
        return http.Response(
          jsonEncode({
            'result': {
              'workspace': demoWorkspace().toJson(),
              'provider': 'fixture/local',
              'reused': false,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(gateway.close);
    final result = await gateway.execute(
      NovelCommand(
        requestId: 'test',
        expectedRevision: 0,
        operation: 'rebuildMemory',
        payload: {},
      ),
    );
    expect(result.workspace.title, '雨夜来信');
    expect(result.provider, 'fixture/local');
  });
  test('确定的操作拒绝不标记结果未知', () async {
    final gateway = HttpNovelGateway(
      endpoint: Uri.parse('http://127.0.0.1:4100'),
      token: 'session',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': '版本冲突'},
          }),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(gateway.close);
    await expectLater(
      gateway.execute(
        NovelCommand(
          requestId: 'test',
          expectedRevision: 0,
          operation: 'rebuildMemory',
          payload: {},
        ),
      ),
      throwsA(
        isA<GatewayFailure>()
            .having((e) => e.message, 'message', '版本冲突')
            .having((e) => e.uncertain, 'uncertain', false),
      ),
    );
  });
}
