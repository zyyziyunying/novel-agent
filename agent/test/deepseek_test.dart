import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_agent/novel_agent.dart';
import 'package:novel_contracts/novel_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('Genkit DeepSeek 插件发送 JSON 模式、token 上限和思考配置并解析正文', () async {
    Json? requestBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/models')) {
        return http.Response(
          jsonEncode({
            'object': 'list',
            'data': [
              {
                'id': 'deepseek-flash',
                'object': 'model',
                'created': 1,
                'owned_by': 'deepseek',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      expect(request.url.host, 'api.deepseek.com');
      expect(request.headers['authorization'], 'Bearer test-key');
      requestBody = jsonDecode(request.body) as Json;
      return http.Response(
        jsonEncode({
          'id': 'test-response',
          'object': 'chat.completion',
          'created': 1,
          'model': 'deepseek-flash',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': jsonEncode({'title': '邮戳', 'body': '林舟尚不知道凶手是谁。'}),
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 100,
            'completion_tokens': 20,
            'total_tokens': 120,
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final ai = Genkit(
      plugins: [deepSeek(apiKey: 'test-key', httpClient: client)],
    );
    final draft = await DeepSeekNovelModel(
      ai,
    ).write(writingContext(demoWorkspace()), '调查信封');
    expect(draft.body, '林舟尚不知道凶手是谁。');
    expect(requestBody!['model'], 'deepseek-flash');
    expect(requestBody!['response_format'], {'type': 'json_object'});
    expect(requestBody!['max_tokens'], 8192);
    expect(requestBody!['thinking'], {'type': 'disabled'});
    expect(draft.usage, isNotEmpty);
  });

  test('Genkit Flow 经 JSON 边界接受操作并返回工作区', () async {
    final ai = Genkit();
    final repository = InMemoryWorkspaceRepository(demoWorkspace());
    final runtime = NovelRuntime(
      ai,
      NovelService(repository, FixtureNovelModel()),
    );
    final result = await runtime.action.runRaw({
      'requestId': 'flow-test',
      'expectedRevision': 0,
      'operation': 'proposeChapter',
      'payload': {'instruction': '续写'},
    });
    expect(result.result['workspace']['proposals'], hasLength(1));
    expect(repository.workspace.chapters, hasLength(2));
  });
}
