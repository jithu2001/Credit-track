import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../connection/business_connection.dart';
import '../providers.dart';
import '../upgrade/upgrade_gate.dart';

/// An error answer from the WholeFlow app API:
/// `{"error": {"code", "message", "details", "hint"}}` with its HTTP status.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, {this.details, this.hint});

  final int status;
  final String code;
  final String message;
  final String? details;
  final String? hint;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// The WholeFlow app API of the connected business
/// (`<base_url>/api/v1/…`, docs/API_PLAN.md), signed in with the same login
/// as the rest of the app.
class ApiClient {
  ApiClient({required this.baseUrl, required this.token, this.headers = const {}, http.Client? client})
    : _http = client ?? http.Client();

  /// The business address, e.g. `https://api.jitsuji.xyz/b/demo`.
  final String baseUrl;

  /// The current access token (refreshed when expired); null when signed out.
  final Future<String?> Function() token;

  /// Sent with every request: the app version and platform
  /// (`X-App-Version`, `X-App-Platform`), so the server can refuse versions
  /// that are too old.
  final Map<String, String> headers;
  final http.Client _http;

  static const timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) => _send('GET', path, query: query);

  /// Changes data; [body] is sent as JSON.
  Future<Map<String, dynamic>> put(String path, Object body) => _send('PUT', path, body: body);
  Future<Map<String, dynamic>> post(String path, Object body) => _send('POST', path, body: body);
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final t = await token();
    if (t == null) throw const ApiException(401, 'UNAUTHENTICATED', 'Sign in again.');
    final req = http.Request(method, uri)
      ..headers.addAll(headers)
      ..headers.addAll({'Authorization': 'Bearer $t', 'Accept': 'application/json'});
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    Object? answer;
    try {
      answer = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      answer = null;
    }
    if (res.statusCode == 200 && answer is Map<String, dynamic>) return answer;
    final e = answer is Map && answer['error'] is Map ? answer['error'] as Map : const {};
    if (res.statusCode == 426) UpgradeGate.trigger(e['message'] as String?);
    throw ApiException(
      res.statusCode,
      (e['code'] as String?) ?? 'HTTP_${res.statusCode}',
      (e['message'] as String?) ?? 'Request failed',
      details: e['details'] as String?,
      hint: e['hint'] as String?,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final connection = ref.watch(businessConnectionProvider);
  final auth = ref.watch(supabaseProvider).auth;
  return ApiClient(
    baseUrl: connection.baseUrl,
    headers: AppInfo.current.headers,
    token: () async {
      var session = auth.currentSession;
      if (session == null) return null;
      if (session.isExpired) session = (await auth.refreshSession()).session;
      return session?.accessToken;
    },
  );
});
