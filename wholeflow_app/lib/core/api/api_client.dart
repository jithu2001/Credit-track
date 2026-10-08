import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../connection/business_connection.dart';
import '../providers.dart';

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
  ApiClient({required this.baseUrl, required this.token, http.Client? client}) : _http = client ?? http.Client();

  /// The business address, e.g. `https://api.jitsuji.xyz/b/demo`.
  final String baseUrl;

  /// The current access token (refreshed when expired); null when signed out.
  final Future<String?> Function() token;
  final http.Client _http;

  static const timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final t = await token();
    if (t == null) throw const ApiException(401, 'UNAUTHENTICATED', 'Sign in again.');
    final res = await _http.get(uri, headers: {'Authorization': 'Bearer $t', 'Accept': 'application/json'}).timeout(timeout);
    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      body = null;
    }
    if (res.statusCode == 200 && body is Map<String, dynamic>) return body;
    final e = body is Map && body['error'] is Map ? body['error'] as Map : const {};
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
    token: () async {
      var session = auth.currentSession;
      if (session == null) return null;
      if (session.isExpired) session = (await auth.refreshSession()).session;
      return session?.accessToken;
    },
  );
});
