/// Build-time configuration, passed with
/// `--dart-define-from-file=env/hosted.json` (see README).
///
/// The apps contain no business address or key: on first launch they ask for
/// the business's reference key, look it up on the WholeFlow server
/// ([controlUrl]) and remember the connection.
abstract final class Env {
  static const controlUrl = String.fromEnvironment('CONTROL_URL', defaultValue: 'https://api.jitsuji.xyz');
}
