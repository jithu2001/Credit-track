package com.wholeflow.wholeflow_app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The one check no plugin covers: whether Developer Options are on (the
    // switch that makes mock-location apps selectable). Read by
    // DeviceIntegrity on the Dart side before a shop check-in.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wholeflow/device_integrity").setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeveloperModeEnabled" -> result.success(
                    Settings.Global.getInt(contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) != 0
                )
                "openDeveloperSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
