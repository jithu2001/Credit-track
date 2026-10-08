import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Which app this is, and its version, as the server is told on every request
/// (`X-App-Version`, `X-App-Platform`) and as error reports carry it.
class AppInfo {
  const AppInfo({required this.version, required this.platform, required this.flavor});

  /// Used before [load] and in tests.
  static const unknown = AppInfo(version: '0.0.0+0', platform: 'android', flavor: 'owner');

  /// Set once by bootstrap.
  static AppInfo current = unknown;

  /// `<versionName>+<buildNumber>`, e.g. `1.0.0+1`.
  final String version;

  /// `android` or `ios`.
  final String platform;

  /// `owner` or `staff`.
  final String flavor;

  Map<String, String> get headers => {'X-App-Version': version, 'X-App-Platform': platform};

  /// The store listing to update from.
  String get packageId => flavor == 'staff' ? 'com.wholeflow.staff' : 'com.wholeflow.wholeflow_app';

  static Future<AppInfo> load({required String flavor}) async {
    var version = unknown.version;
    try {
      final p = await PackageInfo.fromPlatform();
      version = '${p.version}+${p.buildNumber}';
    } catch (_) {
      // Keep the placeholder; the server treats it like any other version.
    }
    final platform = !kIsWeb && Platform.isIOS ? 'ios' : 'android';
    return current = AppInfo(version: version, platform: platform, flavor: flavor);
  }
}
