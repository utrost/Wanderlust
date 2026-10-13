package com.simiono.wanderlust

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35], manifest=Config.NONE)
class RecordingBatteryTest {
    class Result : MethodChannel.Result {
        var value: Any? = null
        var error: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() { fail("Unexpected method") }
    }
    class FallbackActivity : Activity() {
        val attempts = mutableListOf<Intent>()
        override fun startActivity(intent: Intent) {
            attempts.add(intent)
            if (intent.component != null) throw ActivityNotFoundException()
        }
        override fun startActivityForResult(intent: Intent, code: Int) {
            throw ActivityNotFoundException()
        }
    }
    private fun call(battery: RecordingBattery, method: String) = Result().also {
        battery.handle(MethodCall(method, null), it)
    }
    @Test fun `request targets this package and checks real power state on return`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val battery = RecordingBattery(activity)
        assertEquals(false, battery.status()["exempt"])
        val result = call(battery, "requestExemption")
        val started = shadowOf(activity).nextStartedActivityForResult
        assertEquals(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, started.intent.action)
        assertEquals("package:${activity.packageName}", started.intent.data.toString())
        assertEquals("busy", call(battery, "requestExemption").error)
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        shadowOf(power).setIgnoringBatteryOptimizations(activity.packageName, true)
        assertTrue(battery.onActivityResult(started.requestCode))
        assertEquals(true, (result.value as Map<*, *>)["exempt"])
        assertEquals(true, (call(battery, "requestExemption").value as Map<*, *>)["exempt"])
        assertNull(shadowOf(activity).nextStartedActivityForResult)
    }
    @Test fun `refusal remains false and explanation choice persists on this device`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val battery = RecordingBattery(activity)
        call(battery, "markReviewed")
        assertEquals(true, RecordingBattery(activity).status()["reviewed"])
        val result = call(battery, "requestExemption")
        assertTrue(battery.onActivityResult(4102))
        assertEquals(false, (result.value as Map<*, *>)["exempt"])
        assertFalse(battery.onActivityResult(4101))
        val waiting = call(battery, "requestExemption")
        battery.close()
        assertEquals("cancelled", waiting.error)
    }
    @Test fun `unavailable OEM screens fall back and failed requests can retry`() {
        val activity = Robolectric.buildActivity(FallbackActivity::class.java).setup().get()
        val maker = Build.MANUFACTURER
        try {
            ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", "HONOR")
            val battery = RecordingBattery(activity)
            assertEquals(true, call(battery, "openSettings").value)
            assertEquals(3, activity.attempts.size)
            assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, activity.attempts.last().action)
            assertEquals("package:${activity.packageName}", activity.attempts.last().data.toString())
            assertEquals("unavailable", call(battery, "requestExemption").error)
            assertEquals("unavailable", call(battery, "requestExemption").error)
        } finally {
            ReflectionHelpers.setStaticField(Build::class.java, "MANUFACTURER", maker)
        }
    }
}
