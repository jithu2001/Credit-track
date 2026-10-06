import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env.dart';
import '../errors/app_failure.dart';

part 'business_connection.g.dart';

/// Which business (and server address) the app talks to.
class BusinessConnection {
  const BusinessConnection({required this.businessName, required this.baseUrl, required this.anonKey, this.referenceKey});

  /// The build's fixed Supabase project (no reference key, cannot be switched).
  factory BusinessConnection.fixed() =>
      const BusinessConnection(businessName: '', baseUrl: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);

  final String businessName;
  final String baseUrl;
  final String anonKey;

  /// Null for a fixed project.
  final String? referenceKey;

  bool get isHosted => referenceKey != null;

  /// Where the login session is saved. Each hosted business has its own, so
  /// switching business never reuses another business's session. Fixed
  /// projects keep supabase_flutter's default key.
  String? get sessionKey {
    if (!isHosted) return null;
    final slug = Uri.parse(baseUrl).pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'default';
    return 'wf-session-$slug';
  }

  Map<String, String> toJson() => {
    'business_name': businessName,
    'base_url': baseUrl,
    'anon_key': anonKey,
    'reference_key': ?referenceKey,
  };

  static BusinessConnection? fromJson(Map<String, dynamic> j) {
    final base = j['base_url'], key = j['anon_key'];
    if (base is! String || key is! String || base.isEmpty || key.isEmpty) return null;
    return BusinessConnection(
      businessName: (j['business_name'] as String?) ?? '',
      baseUrl: base,
      anonKey: key,
      referenceKey: j['reference_key'] as String?,
    );
  }
}

/// The connection chosen on the connect screen, kept in shared preferences.
class ConnectionStore {
  ConnectionStore(this._prefs);

  static const _key = 'business_connection';
  final SharedPreferences _prefs;

  BusinessConnection? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return BusinessConnection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(BusinessConnection c) => _prefs.setString(_key, jsonEncode(c.toJson()));

  Future<void> clear() => _prefs.remove(_key);
}

/// A reference key looks like `JMJM-7KQ2-XW9P-4HTD`. Spaces, dashes and case
/// don't matter (the server normalises too); this only rejects obvious typos
/// before a network call.
String? normalizeReferenceKey(String input) {
  final raw = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (raw.length < 14 || raw.length > 40) return null;
  final prefix = raw.substring(0, raw.length - 12);
  final rest = raw.substring(raw.length - 12);
  return '$prefix-${rest.substring(0, 4)}-${rest.substring(4, 8)}-${rest.substring(8)}';
}

/// The WholeFlow server's public lookup: reference key → business address.
class ControlApi {
  ControlApi({http.Client? client, String? baseUrl}) : _client = client ?? http.Client(), _base = baseUrl ?? Env.controlUrl;

  final http.Client _client;
  final String _base;

  Future<BusinessConnection> connect(String referenceKey) async {
    final key = normalizeReferenceKey(referenceKey);
    if (key == null) {
      throw const AppFailure(FailureKind.invalidInput, 'That does not look like a reference key. Check it and try again.');
    }
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_base/control/connect').replace(queryParameters: {'key': key}))
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const AppFailure(FailureKind.network);
    } on TimeoutException {
      throw const AppFailure(FailureKind.network);
    } on http.ClientException {
      throw const AppFailure(FailureKind.network);
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode == 200 && body != null) {
      final c = BusinessConnection.fromJson({...body, 'reference_key': key});
      if (c != null) return c;
    }
    final message = (body?['error'] as Map?)?['message'] as String?;
    throw switch (res.statusCode) {
      404 => AppFailure(FailureKind.notFound, message ?? 'No business has this reference key.'),
      400 || 429 => AppFailure(FailureKind.invalidInput, message),
      _ when res.statusCode >= 500 => const AppFailure(FailureKind.server),
      _ => AppFailure(FailureKind.unknown, message),
    };
  }
}

/// The connection the running app uses. Overridden in bootstrap.
@Riverpod(keepAlive: true)
BusinessConnection businessConnection(Ref ref) => BusinessConnection.fixed();

/// Closes the current business and shows the connect screen. Overridden in
/// bootstrap; a no-op in tests.
@Riverpod(keepAlive: true)
Future<void> Function() switchBusiness(Ref ref) => () async {};
