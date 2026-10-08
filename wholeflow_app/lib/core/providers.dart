import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'providers.g.dart';

/// The client for the business's login and data API on the WholeFlow server
/// (GoTrue + PostgREST, through the supabase_flutter package). Overridden in
/// bootstrap once a business is connected, and in tests.
@Riverpod(keepAlive: true)
SupabaseClient supabase(Ref ref) => throw UnimplementedError('supabaseProvider must be overridden');

/// Loaded in main() before runApp so reads are synchronous.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// Fetches every row of a PostgREST query in pages of [pageSize].
Future<List<Map<String, dynamic>>> fetchAll(
  PostgrestTransformBuilder<List<Map<String, dynamic>>> Function(int from, int to) page, {
  int pageSize = 500,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (var from = 0; ; from += pageSize) {
    final batch = await page(from, from + pageSize - 1);
    rows.addAll(batch);
    if (batch.length < pageSize) return rows;
  }
}
