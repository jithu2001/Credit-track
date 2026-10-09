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
