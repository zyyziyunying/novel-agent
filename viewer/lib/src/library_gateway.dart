import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:novel_contracts/novel_contracts.dart';

import 'gateway.dart';

class LibraryResult {
  const LibraryResult(this.workspace, this.provider, this.modelAvailable);
  final LibraryWorkspace workspace;
  final String? provider;
  final bool modelAvailable;
  factory LibraryResult.fromJson(Object? value) {
    final j = object(value, {
      'workspace',
      'provider',
      'modelAvailable',
      'reused',
    });
    if (j['modelAvailable'] is! bool || j['reused'] is! bool) {
      throw const FormatException('需要布尔值');
    }
    return LibraryResult(
      LibraryWorkspace.fromJson(j['workspace']),
      j['provider'] == null ? null : readText(j['provider']),
      j['modelAvailable'],
    );
  }
}

abstract interface class LibraryGateway {
  Future<LibraryResult> load();
  Future<LibraryResult> execute(LibraryCommand command);
  void close();
}

class HttpLibraryGateway implements LibraryGateway {
  HttpLibraryGateway({
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
  Future<LibraryResult> load() => _send(
    () => _client.get(endpoint.resolve('/libraryWorkspace'), headers: _headers),
    action: false,
  );
  @override
  Future<LibraryResult> execute(LibraryCommand command) => _send(
    () => _client.post(
      endpoint.resolve('/libraryAction'),
      headers: _headers,
      body: jsonEncode({'data': command.toJson()}),
    ),
    action: true,
  );
  Future<LibraryResult> _send(
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
      return LibraryResult.fromJson(action ? (value as Json)['result'] : value);
    } on Object {
      throw GatewayFailure('Agent 响应不符合多作品工作台契约。', uncertain: action);
    }
  }

  @override
  void close() => _client.close();
}
