/// Build-time configuration, passed with
/// `--dart-define-from-file=env/<name>.json` (see README).
///
/// Two ways to build the apps:
///  * **Hosted (default):** no Supabase settings. On first launch the app asks
///    for the business's reference key, looks it up on the WholeFlow server
///    ([controlUrl]) and remembers the connection.
///  * **Fixed project:** `SUPABASE_URL` + `SUPABASE_ANON_KEY` are built in and
///    the connect screen is skipped (a business still on its own Supabase
///    project, and development).
///
/// Only a project URL and the publishable (anon) key belong here. The
/// service-role key must never be part of the app.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const controlUrl = String.fromEnvironment('CONTROL_URL', defaultValue: 'https://api.jitsuji.xyz');

  /// True when the build has a fixed Supabase project.
  static bool get hasFixedProject => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
