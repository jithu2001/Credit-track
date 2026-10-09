# R8 rules for release builds (isMinifyEnabled in build.gradle.kts).
# Flutter adds its own engine rules, and the plugins used here (geolocator,
# url_launcher, share_plus, package_info_plus, shared_preferences,
# mobile_scanner, dynamic_color) ship their own consumer rules.

# Flutter's deferred-components support references Play Core classes that this
# app doesn't include.
-dontwarn com.google.android.play.core.**

# The device-integrity method channel in MainActivity is called by name from Dart.
-keep class com.wholeflow.wholeflow_app.MainActivity { *; }
