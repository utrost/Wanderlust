package com.simiono.wanderlust

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.content.pm.PackageManager
import android.Manifest
import android.hardware.*
import android.location.*
import android.os.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.*

/** Started service: no Flutter engine, event subscription, or activity is needed to record. */
class RecordingService : Service() {
    private val evidenceWorker = Executors.newSingleThreadScheduledExecutor()
    private var evidenceWatch: ScheduledFuture<*>? = null
    @Volatile private var workerBeat = 0L
    @Volatile private var callbackBeat = 0L
    @Volatile private var mainBeat = 0L
    @Volatile private var wakeLockEnabled: Boolean? = null
    private val mainPulse = object : Runnable {
        override fun run() {
            mainBeat = SystemClock.elapsedRealtime()
            if (activeId != null) main.postDelayed(this, 30000)
        }
    }
    private var receiverRegistered = false
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { evidence(intent?.action ?: "broadcast") }
    }
    private fun evidence(event: String) {
        val id = activeId ?: return
        val wall = System.currentTimeMillis()
        val elapsed = SystemClock.elapsedRealtime()
        val uptime = SystemClock.uptimeMillis()
        val workerAt = workerBeat
        val callbackAt = callbackBeat
        val mainAt = mainBeat
        val enabled = wakeLockEnabled
        try { evidenceWorker.execute {
            try {
                val power = getSystemService(POWER_SERVICE) as PowerManager
                val data = JSONObject().put("event", event).put("wall", wall)
                    .put("elapsed", elapsed).put("uptime", uptime).put("pid", android.os.Process.myPid())
                    .put("writeElapsed", SystemClock.elapsedRealtime()).put("workerAt", workerAt).put("callbackAt", callbackAt).put("mainAt", mainAt)
                    .put("interactive", power.isInteractive).put("idle", power.isDeviceIdleMode)
                    .put("powerSave", power.isPowerSaveMode).put("batteryExempt", power.isIgnoringBatteryOptimizations(packageName))
                    .put("wakeLockHeld", lock?.isHeld == true)
                    .put("wakeLockEnabled", enabled ?: JSONObject.NULL)
                    .put("schema", 2).put("sdk", Build.VERSION.SDK_INT).put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL)
                systemEvidence(data)
                preferences(this).getString("database", null)?.let { path ->
                    RecordingJournal(path).use { it.evidence(id, data) }
                }
            } catch (e: Exception) { android.util.Log.w("WanderlustEvidence", "Evidence write failed", e) }
        } } catch (_: RejectedExecutionException) { /* Service already destroyed. */ }
    }
    /** These are Android's observations, not our own service-state flags. */
    @Suppress("DEPRECATION")
    private fun systemEvidence(data: JSONObject) {
        fun collect(name: String, read: () -> Unit) {
            try { read() } catch (e: Exception) { data.put(name + "Error", e.javaClass.simpleName) }
        }
        collect("process") {
            val process = ActivityManager.RunningAppProcessInfo()
            ActivityManager.getMyMemoryState(process)
            data.put("importance", process.importance).put("lastTrimLevel", process.lastTrimLevel)
        }
        collect("service") {
            val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            // Since API 26 this returns only our own application's services.
            val service = manager.getRunningServices(100).firstOrNull {
                it.service.className == RecordingService::class.java.name
            }
            data.put("serviceReported", service != null)
            if (service != null) {
                data.put("serviceForeground", service.foreground).put("serviceStarted", service.started)
                    .put("servicePid", service.pid).put("serviceActiveSince", service.activeSince)
            }
            if (Build.VERSION.SDK_INT >= 28) data.put("backgroundRestricted", manager.isBackgroundRestricted)
            if (Build.VERSION.SDK_INT >= 29) data.put("foregroundServiceType", foregroundServiceType)
        }
        collect("power") {
            val power = getSystemService(POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= 28) data.put("locationPowerSaveMode", power.locationPowerSaveMode)
        }
        collect("standby") {
            val power = getSystemService(POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= 33) data.put("lowPowerStandbyEnabled", power.isLowPowerStandbyEnabled)
            if (Build.VERSION.SDK_INT >= 34) data.put("lowPowerStandbyExempt", power.isExemptFromLowPowerStandby)
        }
        collect("permissions") {
            data.put("fineLocation", checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
                .put("coarseLocation", checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED)
                .put("notificationsEnabled", notifications.areNotificationsEnabled())
                .put("gpsEnabled", locations.isProviderEnabled(LocationManager.GPS_PROVIDER))
        }
        collect("version") {
            val info = packageManager.getPackageInfo(packageName, 0)
            data.put("build", if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong())
        }
    }
    private fun acquireRecordingLock() {
        val acquired = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Wanderlust:recording")
        acquired.setReferenceCounted(false)
        lock = acquired
        if (Build.VERSION.SDK_INT >= 33) {
            // isHeld() remains true even when Android disables the lock's effect.
            acquired.setStateListener(evidenceWorker) { enabled ->
                wakeLockEnabled = enabled
                evidence(if (enabled) "wake_lock_enabled" else "wake_lock_disabled")
            }
        }
        acquired.acquire()
        evidence("wake_lock_acquired")
    }
    private var journal: RecordingJournal? = null
    @Volatile private var activeId: Long? = null
    private var policy: RecordingPolicy? = null
    private var listener: LocationListener? = null
    private var watch: ScheduledFuture<*>? = null
    private var lock: PowerManager.WakeLock? = null
    private lateinit var callbacks: HandlerThread
    private var lastReceived = 0L
    private var hasFreshFix = false
    private var lastAttempt = 0L
    private var cadence = 0L
    private var generation = 0
    private var closing = false
    private var sessionStarted = 0L
    private var metrics = JSONObject()
    private var provider = ""
    private var motionArmed = false
    private val motion = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) { worker.execute {
            motionArmed = false
            policy?.motion(SystemClock.elapsedRealtime())
            if (activeId != null) requestUpdates()
        } }
    }
    private val locations get() = getSystemService(LOCATION_SERVICE) as LocationManager
    private val notifications get() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    private val sensors get() = getSystemService(SENSOR_SERVICE) as SensorManager

    override fun onCreate() {
        super.onCreate()
        current = this
        callbacks = HandlerThread("walk-location-callbacks").also { it.start() }
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Walk recording", NotificationManager.IMPORTANCE_LOW))
            notifications.createNotificationChannel(NotificationChannel(ALERT_CHANNEL, "Recording needs attention", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }
    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (closing) {
            reply(intent?.getStringExtra("request"), null, IllegalStateException("Previous recording is finishing; please retry"))
            return START_NOT_STICKY
        }
        if (intent?.action == STOP) {
            val id = intent.getLongExtra("walkId", -1)
            worker.execute {
                if (activeId == null) {
                    try {
                        preferences(this).getString("database", null)?.let { path ->
                            RecordingJournal(path).use { it.finish(id, System.currentTimeMillis(), true) }
                        }
                    } finally { shutdown() }
                } else stopSession(id, false)
            }
            return START_NOT_STICKY
        }
        val request = intent?.getStringExtra("request")
        // Promote immediately, before disk access or GPS. Sticky restarts can be denied:
        // retain the active journal and let the next visible launch offer Continue.
        try {
            val note = notification("Starting your walk…", 0, null)
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(NOTIFICATION_ID, note)
        } catch (e: Exception) {
            reply(request, null, e); stopSelf(); return START_NOT_STICKY
        }
        worker.execute {
            try {
                if (activeId == null) {
                    val path = preferences(this).getString("database", null) ?: error("Recording database is unavailable")
                    val j = RecordingJournal(path).also { journal = it }
                    val existing = j.state()
                    val resume = if (intent == null) {
                        if (existing?.get("active") != true) { shutdown(); return@execute }
                        existing["walkId"] as Long
                    } else intent.getLongExtra("resumeId", -1).takeIf { it >= 0 }
                    val id = j.start(intent?.getStringExtra("activity") ?: "walk", System.currentTimeMillis(), resume, intent?.getLongExtra("manualInterval", 0) ?: 0)
                    activeId = id
                    val state = j.state()!!
                    sessionStarted = parseTime(state["startedAt"] as String)
                    policy = RecordingPolicy(state["activity"] == "cycle", SystemClock.elapsedRealtime(), (state["meters"] as Double), (state["manualInterval"] as Long).takeIf { it > 0 })
                    metrics = JSONObject(state["diagnostics"] as Map<*, *>)
                    lastReceived = SystemClock.elapsedRealtime()
                    acquireRecordingLock()
                    main.post(mainPulse)
                    workerBeat = SystemClock.elapsedRealtime()
                    evidence(if (intent == null) "sticky_start" else if (resume != null) "resume" else "start")
                    val filter = IntentFilter().apply {
                        addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_SCREEN_OFF)
                        addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                        addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
                    }
                    if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    else registerReceiver(screenReceiver, filter)
                    receiverRegistered = true
                    evidenceWatch = evidenceWorker.scheduleWithFixedDelay({ evidence("heartbeat") }, 30, 30, TimeUnit.SECONDS)
                    requestUpdates()
                    watch = worker.scheduleWithFixedDelay({ tick() }, 5, 5, TimeUnit.SECONDS)
                } else if (intent?.hasExtra("resumeId") == true) {
                    check(intent.getLongExtra("resumeId", -1) == activeId) { "A different walk is active" }
                }
                updateNotification()
                reply(request, mapOf("walkId" to activeId), null)
            } catch (e: Exception) {
                reply(request, null, e)
                evidence("startup_failure:" + e.javaClass.simpleName)
                // Keep durable session resumable, even when provider setup failed.
                shutdown()
            }
        }
        return START_STICKY
    }

    private fun requestUpdates() {
        val p = policy ?: return
        evidence("request_updates")
        generation++
        val epoch = generation
        listener?.let { locations.removeUpdates(it) }
        cadence = p.interval(SystemClock.elapsedRealtime())
        lastAttempt = SystemClock.elapsedRealtime()
        val freshListener = object : LocationListener {
            override fun onLocationChanged(location: Location) { callbackBeat = SystemClock.elapsedRealtime(); val copy = Location(location); worker.execute {
                if (activeId != null && epoch == generation) accept(copy)
            } }
            override fun onProviderEnabled(name: String) { worker.execute { if (activeId != null && epoch == generation) requestUpdates() } }
            override fun onProviderDisabled(name: String) { evidence("provider_disabled:$name") }
            @Deprecated("Legacy Android callback")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        listener = freshListener
        // Platform providers only: GPS first, network assists acquisition/poor reception.
        for (name in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (locations.allProviders.contains(name)) {
                try { locations.requestLocationUpdates(name, cadence, 0f, freshListener, callbacks.looper) }
                catch (_: IllegalArgumentException) { /* Provider disappeared; retry later. */ }
            }
        }
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
        if (p.stationary && !motionArmed && sensor != null) motionArmed = sensors.requestTriggerSensor(motion, sensor)
        else if (!p.stationary && motionArmed) { sensors.cancelTriggerSensor(motion, sensor); motionArmed = false }
    }

    private fun accept(location: Location) {
        try {
            val j = journal ?: return
            val id = activeId ?: return
            val now = System.currentTimeMillis()
            val elapsed = SystemClock.elapsedRealtime()
            val age = now - location.time
            if (!location.latitude.isFinite() || !location.longitude.isFinite() ||
                location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0 ||
                !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0 ||
                age < -5000 || location.time < sessionStarted) return
            val fresh = age <= 30000
            val s = j.state() ?: return
            if (location.time <= s["lastFix"] as Long) return
            // Prefer a recent precise GPS fix over a much poorer network callback.
            if (location.provider != LocationManager.GPS_PROVIDER && provider == LocationManager.GPS_PROVIDER &&
                elapsed - lastReceived < 10000 && location.accuracy > 25) return
            val p = policy ?: return
            val speed = if (location.hasSpeed() && Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy() &&
                location.speedAccuracyMetersPerSecond <= 0.7f) location.speed.toDouble() else null
            val bearing = if (location.hasBearing() && (speed ?: 0.0) > 0.7) location.bearing.toDouble() else null
            p.add(RecordingPolicy.Fix(location.latitude, location.longitude, location.accuracy.toDouble(), location.time, speed, bearing), elapsed)
            val count = metrics.optInt("receivedFixes") + 1
            val priorTime = s["lastFix"] as Long
            metrics.put("version", 1).put("receivedFixes", count)
                .put("staleFixes", metrics.optInt("staleFixes") + if (fresh) 0 else 1)
                .put("requestedIntervalSeconds", cadence / 1000)
                .put("streamRestarts", s["restarts"])
                .put("lastReportedProvider", location.provider)
                .put("meanAccuracyM", (metrics.optDouble("meanAccuracyM", 0.0) * (count-1) + location.accuracy) / count)
                .put("maxAccuracyM", maxOf(metrics.optDouble("maxAccuracyM", 0.0), location.accuracy.toDouble()))
                .put("maxFixAgeMs", maxOf(metrics.optLong("maxFixAgeMs"), age.coerceAtLeast(0)))
            if (fresh && !metrics.has("firstFreshFixMs")) metrics.put("firstFreshFixMs", (now-sessionStarted).coerceAtLeast(0))
            if (priorTime > 0) metrics.put("maxFixIntervalMs", maxOf(metrics.optLong("maxFixIntervalMs"), location.time-priorTime))
            // Commit before changing the externally visible latest-fix/notification state.
            if (!j.append(id, location, p.meters, metrics)) return
            provider = location.provider ?: ""
            if (fresh) {
                lastReceived = elapsed
                hasFreshFix = true
                notifications.cancel(ALERT_ID)
            }
            if (p.interval(elapsed) != cadence) requestUpdates()
            updateNotification()
        } catch (e: Exception) { storageFailure(e) }
    }

    private fun tick() {
        if (activeId == null) return
        workerBeat = SystemClock.elapsedRealtime()
        try {
            val elapsed = SystemClock.elapsedRealtime()
            val stalled = elapsed - lastReceived >= 45000
            if (stalled && elapsed - lastAttempt >= 60000) {
                evidence("watchdog_retry")
                journal?.restart()
                requestUpdates()
            } else if (!stalled && policy?.interval(elapsed) != cadence) requestUpdates()
            if (elapsed - lastReceived >= 120000 && journal?.state()?.get("alerted") == false) {
                journal?.markAlerted()
                notifyAttention("GPS is unavailable", "Your walk is still open. We’re trying to reconnect.")
            }
            updateNotification()
        } catch (_: SecurityException) {
            evidence("permission_failure")
            notifyAttention("Location permission changed", "Open Wanderlust to continue your walk.")
            shutdown()
        } catch (e: Exception) { storageFailure(e) }
    }
    private fun storageFailure(error: Exception) {
        evidence("recording_failure:" + error.javaClass.simpleName)
        notifyAttention("Recording paused", "Your saved route is safe. Open Wanderlust to check recording.")
        shutdown()
    }
    private fun notifyAttention(title: String, text: String) {
        try {
            val b = builder(ALERT_CHANNEL).setSmallIcon(R.drawable.ic_walk_notification)
                .setContentTitle(title).setContentText(text).setContentIntent(openApp())
                .setAutoCancel(true).setOnlyAlertOnce(true)
            if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_DEFAULT)
            notifications.notify(ALERT_ID, b.build())
        } catch (_: SecurityException) { /* User can decline notifications. */ }
    }
    private fun updateNotification() {
        val s = journal?.state() ?: return
        val text = if (SystemClock.elapsedRealtime()-lastReceived >= 45000) "GPS paused · reconnecting" else if (!hasFreshFix) "Finding your location…" else String.format(Locale.getDefault(), "%.2f km · %s", (s["meters"] as Double)/1000, if (s["activity"] == "cycle") "Ride in progress" else "Walk in progress")
        notifications.notify(NOTIFICATION_ID, notification(text, sessionStarted, activeId))
    }
    private fun builder(channel: String): Notification.Builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
    private fun openApp(): PendingIntent = PendingIntent.getActivity(this, 400,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun notification(text: String, started: Long, id: Long?): Notification {
        val b = builder(CHANNEL).setSmallIcon(R.drawable.ic_walk_notification)
            .setContentTitle("Wanderlust").setContentText(text).setContentIntent(openApp())
            .setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE)
        if (started > 0) b.setWhen(started).setUsesChronometer(true)
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        if (id != null) b.addAction(Notification.Action.Builder(null, "Stop",
            PendingIntent.getService(this, id.hashCode(), Intent(this, RecordingService::class.java).setAction(STOP).putExtra("walkId", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)).build())
        return b.build()
    }
    private fun stopSession(id: Long, interrupted: Boolean) {
        try {
            if (activeId != id) return // An old notification cannot stop another walk.
            evidence("stop")
            journal?.finish(id, System.currentTimeMillis(), interrupted)
            notifications.cancel(ALERT_ID)
            shutdown()
        } catch (e: Exception) { storageFailure(e) }
    }
    private fun releaseResources() {
        evidenceWatch?.cancel(false); evidenceWatch = null
        if (receiverRegistered) { unregisterReceiver(screenReceiver); receiverRegistered = false }
        main.removeCallbacks(mainPulse)
        evidence("wake_lock_releasing")
        // Remove the listener before shutting down its executor.
        if (Build.VERSION.SDK_INT >= 33) lock?.setStateListener(evidenceWorker, null)
        activeId = null; generation++
        watch?.cancel(false); watch = null
        listener?.let { try { locations.removeUpdates(it) } catch (_: Exception) {} }; listener = null
        if (motionArmed) sensors.cancelTriggerSensor(motion, sensors.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION))
        motionArmed = false
        lock?.let { if (it.isHeld) it.release() }; lock = null
        journal?.close(); journal = null
    }
    private fun shutdown() {
        closing = true
        releaseResources()
        main.post { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    }
    override fun onTaskRemoved(rootIntent: Intent?) {
        evidence("task_removed")
        super.onTaskRemoved(rootIntent)
    }
    override fun onTrimMemory(level: Int) {
        evidence("trim_memory:$level")
        super.onTrimMemory(level)
    }
    override fun onDestroy() {
        evidence("service_destroy")
        if (current === this) current = null
        worker.execute { releaseResources(); callbacks.quitSafely(); evidenceWorker.shutdown() }
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "wanderlust_recording_v2"
        private const val ALERT_CHANNEL = "wanderlust_recording_attention"
        private const val NOTIFICATION_ID = 5411
        private const val ALERT_ID = 5412
        private const val STOP = "com.simiono.wanderlust.STOP_RECORDING"
        internal val worker = Executors.newSingleThreadScheduledExecutor()
        private val main = Handler(Looper.getMainLooper())
        @Volatile private var current: RecordingService? = null
        private val replies = ConcurrentHashMap<String, MethodChannel.Result>()
        private fun preferences(context: Context) = context.getSharedPreferences("native_recording", MODE_PRIVATE)
        private fun reply(request: String?, value: Any?, error: Exception?) {
            val result = request?.let { replies.remove(it) } ?: return
            main.post { if (error == null) result.success(value) else result.error("recording", error.message, null) }
        }
        private fun parseTime(value: String) = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }.parse(value)!!.time

        fun visibility(visible: Boolean) { current?.evidence(if (visible) "app_visible" else "app_hidden") }
        fun handle(activity: Activity, visible: Boolean, call: MethodCall, result: MethodChannel.Result) {
            val path = call.argument<String>("database")
            if (path == null || File(path).canonicalPath != activity.getDatabasePath("wanderlust.db").canonicalPath) {
                result.error("database", "Recording requires the app journal", null); return
            }
            if (call.method == "start") {
                if (!visible) { result.error("background", "Open Wanderlust to start recording", null); return }
                if (!preferences(activity).edit().putString("database", path).commit()) {
                    result.error("storage", "Could not prepare recording", null); return
                }
                val key = UUID.randomUUID().toString()
                replies[key] = result
                val intent = Intent(activity, RecordingService::class.java).putExtra("request", key)
                    .putExtra("activity", if (call.argument<String>("activity") == "cycle") "cycle" else "walk")
                call.argument<Number>("intervalSeconds")?.toInt()?.takeIf { it in setOf(2, 5, 10, 20) }?.let {
                    intent.putExtra("manualInterval", it * 1000L)
                }
                call.argument<Number>("resumeId")?.let { intent.putExtra("resumeId", it.toLong()) }
                try {
                    if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                } catch (e: Exception) { reply(key, null, e) }
                // An unresponsive service must not leave the UI spinning forever.
                main.postDelayed({ reply(key, null, IllegalStateException("Recording startup timed out; reopen the app to check the walk")) }, 15000)
                return
            }
            if (call.method !in setOf("snapshot", "stop")) { result.notImplemented(); return }
            worker.execute {
                try {
                    val service = current
                    val own = service?.journal == null
                    val j = service?.journal ?: RecordingJournal(path)
                    try {
                        if (call.method == "stop") {
                            val id = call.argument<Number>("walkId")!!.toLong()
                            if (service?.activeId == id) service.stopSession(id, false)
                            else j.finish(id, System.currentTimeMillis(), true)
                            main.post { result.success(null) }
                        } else {
                            val s = j.state()
                            if (s != null) {
                                val id = s["walkId"] as Long
                                val running = service?.activeId == id
                                s["running"] = running
                                s["hasFreshFix"] = running && service!!.hasFreshFix
                                s["stale"] = running && SystemClock.elapsedRealtime() - service!!.lastReceived >= 45000
                                s["intervalSeconds"] = if (running) service!!.cadence / 1000 else 0
                                val after = if (call.argument<Number>("walkId")?.toLong() == id) call.argument<Number>("after")?.toInt() ?: -1 else -1
                                s["points"] = j.points(id, after)
                            }
                            main.post { result.success(s) }
                        }
                    } finally { if (own) j.close() }
                } catch (e: Exception) { main.post { result.error("storage", e.message, null) } }
            }
        }
    }
}
