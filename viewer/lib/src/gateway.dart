import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:novel_contracts/novel_contracts.dart';

class GatewayFailure implements Exception {
  const GatewayFailure(this.message, {this.uncertain = false});
  final String message;
  final bool uncertain;
}

class WorkspaceResult {
  const WorkspaceResult(this.workspace, this.provider);
  final Workspace workspace;
  final String provider;
  factory WorkspaceResult.fromJson(Object? value) {
    final j = object(value, {'workspace', 'provider', 'reused'});
    return WorkspaceResult(
      Workspace.fromJson(j['workspace']),
      readText(j['provider']),
    );
  }
}

abstract interface class NovelGateway {
  Future<WorkspaceResult> load();
  Future<WorkspaceResult> execute(NovelCommand command);
  void close();
}

class HttpNovelGateway implements NovelGateway {
  HttpNovelGateway({
    required this.endpoint,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final Uri endpoint;
  final String token;
  final http.Client _client;
  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'authorization': 'Bearer $token',
  };

  @override
  Future<WorkspaceResult> load() => _send(
    () => _client.get(endpoint.resolve('/workspace'), headers: _headers),
    action: false,
  );

  @override
  Future<WorkspaceResult> execute(NovelCommand command) => _send(
    () => _client.post(
      endpoint.resolve('/novelAction'),
      headers: _headers,
      body: jsonEncode({'data': command.toJson()}),
    ),
    action: true,
  );

  Future<WorkspaceResult> _send(
    Future<http.Response> Function() send, {
    required bool action,
  }) async {
    late http.Response response;
    try {
      response = await send().timeout(const Duration(seconds: 110));
    } on Object {
      throw GatewayFailure('无法连接 Agent 或等待超时，请检查服务地址与会话令牌。', uncertain: action);
    }
    Object? value;
    try {
      value = jsonDecode(response.body);
    } on FormatException {
      throw GatewayFailure('Agent 响应无法读取。', uncertain: action);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final j = value is Json ? value : <String, dynamic>{};
      final error = j['error'];
      final message = error is Json ? error['message'] : j['message'];
      throw GatewayFailure(
        message is String ? message : 'Agent 无法完成操作。',
        uncertain: action && response.statusCode >= 500,
      );
    }
    try {
      if (action && value is Json && value.containsKey('result')) {
        value = value['result'];
      }
      return WorkspaceResult.fromJson(value);
    } on Object {
      throw GatewayFailure('Agent 响应不符合小说工作台契约。', uncertain: action);
    }
  }

  @override
  void close() => _client.close();
}
