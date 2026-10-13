package com.simiono.wanderlust

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** User-initiated battery setup, separate from GPS and notification permissions. */
class RecordingBattery(private val activity: Activity) {
    private val preferences = activity.getSharedPreferences("recording_battery", Context.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null
    private val requestCode = 4102

    fun status(): Map<String, Any> = mapOf(
        "supported" to (Build.VERSION.SDK_INT >= 23),
        "exempt" to (Build.VERSION.SDK_INT < 23 ||
            (activity.getSystemService(Context.POWER_SERVICE) as PowerManager)
                .isIgnoringBatteryOptimizations(activity.packageName)),
        "reviewed" to preferences.getBoolean("reviewed", false),
        "manufacturer" to Build.MANUFACTURER,
    )

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "markReviewed" -> {
                preferences.edit().putBoolean("reviewed", true).apply()
                result.success(null)
            }
            "requestExemption" -> {
                if (status()["exempt"] == true) {
                    result.success(status())
                } else if (pending != null) {
                    result.error("busy", "Battery permission is already open.", null)
                } else {
                    pending = result
                    try {
                        activity.startActivityForResult(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:${activity.packageName}")), requestCode)
                    } catch (_: RuntimeException) {
                        pending = null
                        result.error("unavailable", "Open the app battery settings instead.", null)
                    }
                }
            }
            "openSettings" -> result.success(openSettings())
            else -> result.notImplemented()
        }
    }

    private fun openSettings(): Boolean {
        val maker = Build.MANUFACTURER.lowercase(java.util.Locale.ROOT)
        // OEM entry points vary by model. Fall back to Android's app details.
        val candidates = mutableListOf<Intent>()
        if (maker == "honor" || maker == "huawei") {
            val packages = if (maker == "honor") listOf("com.hihonor.systemmanager", "com.huawei.systemmanager")
                else listOf("com.huawei.systemmanager")
            for (pkg in packages) candidates.add(Intent().setComponent(ComponentName(
                pkg, "$pkg.startupmgr.ui.StartupNormalAppListActivity")))
        }
        candidates.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${activity.packageName}")))
        for (intent in candidates) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: RuntimeException) {
                // Missing/non-exported vendor activity: use the next safe shortcut.
            }
        }
        return false
    }

    fun onActivityResult(code: Int): Boolean {
        if (code != requestCode) return false
        // RESULT_OK is not a reliable permission result; read the actual state.
        val result = pending
        pending = null
        result?.success(status())
        return true
    }

    fun close() {
        pending?.error("cancelled", "Battery setup was closed.", null)
        pending = null
    }
}
