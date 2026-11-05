package com.simiono.wanderlust

import android.content.Context
import android.os.Build
import android.os.StatFs
import java.io.File

/** Read-only metadata. No storage permission, GPS or device identifier access. */
object MapDiagnostics {
    fun environment(context: Context): Map<String, Any> {
        val data = mutableMapOf<String, Any>(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
        )
        runCatching {
            @Suppress("DEPRECATION")
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            @Suppress("DEPRECATION")
            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
            data["build"] = "${info.versionName} ($code)"
        }
        runCatching { data["directory"] = File(context.filesDir, "map-diagnostics").path }
        runCatching { data["availableBytes"] = StatFs(context.filesDir.path).availableBytes }
        return data
    }
}
