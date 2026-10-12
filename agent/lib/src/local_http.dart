import 'dart:convert';
import 'dart:io';

import 'package:genkit/io.dart';
import 'package:novel_contracts/novel_contracts.dart';

Future<void> handleLocalRequest(
  HttpRequest request, {
  required GenkitRouter router,
  required Future<Json> Function() snapshot,
  required String snapshotPath,
  required String origin,
  required String token,
}) async {
  try {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    final callers = request.headers['origin'];
    final authorizations = request.headers['authorization'];
    if ((callers?.length ?? 0) > 1 || (authorizations?.length ?? 0) > 1) {
      response.statusCode = 400;
      response.write(
        jsonEncode({
          'error': {'message': 'Origin 和 Authorization 请求头不能重复。'},
        }),
      );
      await response.close();
      return;
    }
    final caller = callers?.single;
    if (caller != null && caller != origin) {
      response.statusCode = 403;
      response.write(
        jsonEncode({
          'error': {'message': '不允许这个工作台来源。'},
        }),
      );
      await response.close();
      return;
    }
    if (caller == origin) {
      response.headers.set('access-control-allow-origin', origin);
      response.headers.set('vary', 'Origin');
      response.headers.set(
        'access-control-allow-headers',
        'authorization,content-type',
      );
      response.headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');
    }
    if (request.method == 'OPTIONS') {
      response.statusCode = 204;
      await response.close();
      return;
    }
    if (authorizations?.single != 'Bearer $token') {
      response.statusCode = 401;
      response.write(
        jsonEncode({
          'error': {'message': '会话令牌不正确，请使用 Agent 启动时显示的令牌。'},
        }),
      );
      await response.close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == snapshotPath) {
      response.write(jsonEncode(await snapshot()));
      await response.close();
      return;
    }
    if (await router.handleHttpRequest(request)) return;
    response.statusCode = 404;
    response.write(
      jsonEncode({
        'error': {'message': '接口不存在。'},
      }),
    );
    await response.close();
  } on Object {
    try {
      request.response.statusCode = 500;
      request.response.write(
        jsonEncode({
          'error': {'message': '读取或处理工作区失败。'},
        }),
      );
    } on Object {
      // The response may already be committed or the client disconnected.
    }
    try {
      await request.response.close();
    } on Object {
      // A failed cleanup must not escape this unawaited request handler.
    }
  }
}
