package com.simiono.wanderlust

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.os.Looper
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.android.controller.ServiceController
import org.robolectric.shadows.ShadowSystemClock
import java.io.File
import java.time.Duration
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35], manifest=Config.NONE)
class RecordingServiceTest {
    private lateinit var file: File
    private lateinit var controller: ServiceController<RecordingService>
    private val context get() = RuntimeEnvironment.getApplication()
    private val notifications get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun drain() {
        RecordingService.worker.submit {}.get(10, TimeUnit.SECONDS)
        shadowOf(Looper.getMainLooper()).idle()
        RecordingService.worker.submit {}.get(10, TimeUnit.SECONDS)
    }
    @Before fun setup() {
        shadowOf(context).grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.POST_NOTIFICATIONS)
        file = context.getDatabasePath("wanderlust.db")
        file.parentFile!!.mkdirs(); file.delete()
        SQLiteDatabase.openOrCreateDatabase(file, null).use { db ->
            db.execSQL("PRAGMA application_id=1463897668")
            db.execSQL("CREATE TABLE recorded_walk(id INTEGER PRIMARY KEY,started_at TEXT NOT NULL,ended_at TEXT,status TEXT NOT NULL,uid TEXT,trace_metadata TEXT NOT NULL DEFAULT '{}',fingerprint TEXT)")
            db.execSQL("CREATE TABLE recorded_point(walk_id INTEGER NOT NULL REFERENCES recorded_walk(id),seq INTEGER NOT NULL,position TEXT NOT NULL,timestamp TEXT NOT NULL,PRIMARY KEY(walk_id,seq))")
        }
        context.getSharedPreferences("native_recording", Context.MODE_PRIVATE).edit().putString("database", file.path).commit()
        controller = Robolectric.buildService(RecordingService::class.java).create()
        controller.get().onStartCommand(Intent(context, RecordingService::class.java).putExtra("activity", "walk"), 0, 1)
        drain()
    }
    @After fun close() { controller.destroy(); drain(); file.delete() }
    private fun state() = RecordingJournal(file.path).use { it.state()!! }
    private fun accept() {
        val location = Location("gps").apply {
            latitude=53.0; longitude=8.8; accuracy=5f; time=System.currentTimeMillis()
        }
        val method = RecordingService::class.java.getDeclaredMethod("accept", Location::class.java).apply { isAccessible=true }
        RecordingService.worker.submit { method.invoke(controller.get(), location) }.get(10, TimeUnit.SECONDS)
        drain()
    }
    @Test fun `evidence continues while recording worker is blocked without GPS`() {
        drain()
        val entered = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        RecordingService.worker.execute { entered.countDown(); release.await(10, TimeUnit.SECONDS) }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        try {
            val method = RecordingService::class.java.getDeclaredMethod("evidence", String::class.java).apply { isAccessible=true }
            method.invoke(controller.get(), "heartbeat_test")
            val field = RecordingService::class.java.getDeclaredField("evidenceWorker").apply { isAccessible=true }
            (field.get(controller.get()) as java.util.concurrent.ScheduledExecutorService).submit {}.get(5, TimeUnit.SECONDS)
            val diagnostics = state()["diagnostics"] as Map<*, *>
            assertTrue((diagnostics["evidenceLog"] as String).contains("heartbeat_test"))
            assertEquals(0L, state()["pointCount"])
        } finally { release.countDown(); drain() }
    }
    @Test fun `system evidence includes Android classification and unknown lock state`() {
        val method = RecordingService::class.java.getDeclaredMethod("evidence", String::class.java).apply { isAccessible=true }
        method.invoke(controller.get(), "classification_test")
        val field = RecordingService::class.java.getDeclaredField("evidenceWorker").apply { isAccessible=true }
        (field.get(controller.get()) as java.util.concurrent.ScheduledExecutorService).submit {}.get(5, TimeUnit.SECONDS)
        val log = org.json.JSONArray((state()["diagnostics"] as Map<*, *>)["evidenceLog"] as String)
        val entry = (0 until log.length()).map { log.getJSONObject(it) }.last { it.getString("event") == "classification_test" }
        assertEquals(2, entry.getInt("schema"))
        assertTrue(entry.has("importance"))
        assertTrue(entry.has("serviceReported"))
        assertTrue(entry.has("foregroundServiceType"))
        assertTrue(entry.has("lowPowerStandbyEnabled"))
        assertTrue(entry.has("lowPowerStandbyExempt"))
        assertTrue(entry.getBoolean("fineLocation"))
        assertTrue(entry.getBoolean("wakeLockHeld"))
        // No framework state callback in this shadow: held must not imply enabled.
        assertTrue(entry.isNull("wakeLockEnabled"))
    }
    @Test fun `framework disabled lock is recorded even while locally held`() {
        val lock = RecordingService::class.java.getDeclaredField("lock").apply { isAccessible=true }
            .get(controller.get()) as android.os.PowerManager.WakeLock
        val listener = android.os.PowerManager.WakeLock::class.java.getDeclaredField("mListener").apply { isAccessible=true }
            .get(lock) as android.os.PowerManager.WakeLockStateListener
        listener.onStateChanged(false)
        val field = RecordingService::class.java.getDeclaredField("evidenceWorker").apply { isAccessible=true }
        (field.get(controller.get()) as java.util.concurrent.ScheduledExecutorService).submit {}.get(5, TimeUnit.SECONDS)
        val log = org.json.JSONArray((state()["diagnostics"] as Map<*, *>)["evidenceLog"] as String)
        val entry = (0 until log.length()).map { log.getJSONObject(it) }.last { it.getString("event") == "wake_lock_disabled" }
        assertTrue(entry.getBoolean("wakeLockHeld"))
        assertFalse(entry.getBoolean("wakeLockEnabled"))
        assertEquals(true, state()["active"])
    }
    @Test @Config(sdk=[28]) fun `older Android records evidence without wake state listener`() {
        val method = RecordingService::class.java.getDeclaredMethod("evidence", String::class.java).apply { isAccessible=true }
        method.invoke(controller.get(), "legacy_test")
        val field = RecordingService::class.java.getDeclaredField("evidenceWorker").apply { isAccessible=true }
        (field.get(controller.get()) as java.util.concurrent.ScheduledExecutorService).submit {}.get(5, TimeUnit.SECONDS)
        assertTrue(((state()["diagnostics"] as Map<*, *>)["evidenceLog"] as String).contains("legacy_test"))
    }
    @Test fun `capture and notification Stop need no Flutter engine`() {
        accept()
        assertEquals(1L, state()["pointCount"])
        val notification = shadowOf(notifications).getNotification(5411)
        assertNotNull(notification)
        assertTrue(notification.extras.getBoolean("android.showChronometer"))
        val stop = notification.actions.single().actionIntent
        val stopIntent = shadowOf(stop).savedIntent
        controller.get().onStartCommand(stopIntent, 0, 2)
        drain()
        assertEquals(false, state()["active"])
        assertEquals("completed", state()["status"])
        accept() // Already queued/late provider callbacks cannot write after Stop.
        assertEquals(1L, state()["pointCount"])
    }
    @Test fun `service destruction preserves journal and sticky restart resumes same walk`() {
        accept()
        val id = state()["walkId"]
        controller.destroy(); drain()
        assertEquals(true, state()["active"])
        controller = Robolectric.buildService(RecordingService::class.java).create()
        controller.get().onStartCommand(null, 0, 2)
        drain()
        assertEquals(id, state()["walkId"])
        Thread.sleep(5)
        accept()
        assertEquals(2L, state()["pointCount"])
        assertEquals(listOf(1), state()["segments"])
    }
    @Test fun `late fixes are saved but do not masquerade as healthy live GPS`() {
        val started = System.currentTimeMillis() - 120000
        RecordingJournal(file.path).use { it.db.execSQL("UPDATE recorded_walk SET started_at=?", arrayOf(RecordingJournal.iso(started))) }
        val service = controller.get()
        RecordingService::class.java.getDeclaredField("sessionStarted").apply { isAccessible=true }.setLong(service, started)
        val lastReceived = RecordingService::class.java.getDeclaredField("lastReceived").apply { isAccessible=true }
        val before = lastReceived.getLong(service)
        val location = Location("gps").apply {
            latitude=53.0; longitude=8.8; accuracy=5f; time=System.currentTimeMillis()-60000
        }
        val accept = RecordingService::class.java.getDeclaredMethod("accept", Location::class.java).apply { isAccessible=true }
        RecordingService.worker.submit { accept.invoke(service, location) }.get(10, TimeUnit.SECONDS)
        assertEquals(1L, state()["pointCount"])
        assertEquals(before, lastReceived.getLong(service))
        val diagnostics = state()["diagnostics"] as Map<*, *>
        assertEquals(1, diagnostics["staleFixes"])
        assertNull(diagnostics["firstFreshFixMs"])
        accept()
        assertEquals(2L, state()["pointCount"])
        assertNotNull((state()["diagnostics"] as Map<*, *>)["firstFreshFixMs"])
    }
    @Test fun `native watchdog restarts stalled GPS and alerts only once per walk`() {
        val tick = RecordingService::class.java.getDeclaredMethod("tick").apply { isAccessible=true }
        ShadowSystemClock.advanceBy(Duration.ofSeconds(130))
        RecordingService.worker.submit { tick.invoke(controller.get()) }.get(10, TimeUnit.SECONDS)
        assertTrue((state()["restarts"] as Long) > 0)
        assertEquals(true, state()["alerted"])
        assertNotNull(shadowOf(notifications).getNotification(5412))
        accept()
        assertNull(shadowOf(notifications).getNotification(5412))
        ShadowSystemClock.advanceBy(Duration.ofSeconds(130))
        RecordingService.worker.submit { tick.invoke(controller.get()) }.get(10, TimeUnit.SECONDS)
        assertNull(shadowOf(notifications).getNotification(5412))
    }
}
