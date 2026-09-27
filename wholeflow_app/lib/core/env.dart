/// Build-time configuration, passed with
/// `--dart-define-from-file=env/dev.json` (see README).
///
/// Only the project URL and the publishable (anon) key belong here. The
/// service-role key must never be part of the app.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
