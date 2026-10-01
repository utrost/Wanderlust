package com.wanderlust.wanderlust

import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Notification permission is requested only when the user starts a walk. */
class MainActivity : FlutterActivity() {
    private val backupFiles by lazy { BackupFiles(this) }
    private var pendingNotification: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wanderlust/backups")
            .setMethodCallHandler(backupFiles::handle)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wanderlust/about")
            .setMethodCallHandler { call, result ->
                if (call.method == "version") {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success("${info.versionName} (build $code)")
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wanderlust/walking")
            .setMethodCallHandler { call, result ->
                if (call.method != "prepareRecording") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (pendingNotification != null) {
                    result.error("busy", "Notification permission is already being requested.", null)
                } else {
                    val preferences = getSharedPreferences("walking", MODE_PRIVATE)
                    if (preferences.getBoolean("notificationAsked", false)) {
                        // Respect a refusal; users can enable notifications in Android settings.
                        result.success(false)
                    } else {
                        preferences.edit().putBoolean("notificationAsked", true).apply()
                        pendingNotification = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4101)
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4101) {
            pendingNotification?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingNotification = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!backupFiles.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        backupFiles.close()
        pendingNotification?.success(false)
        pendingNotification = null
        super.onDestroy()
    }
}
