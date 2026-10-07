package com.simiono.wanderlust

import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** A second connection to the app journal; all use is serialized on the recorder worker. */
class RecordingJournal(path: String) : AutoCloseable {
    val db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READWRITE)
    init {
        check(db.rawQuery("PRAGMA application_id", null).use { it.moveToFirst(); it.getInt(0) } == 0x57414e44)
        db.execSQL("PRAGMA foreign_keys=ON")
        db.rawQuery("PRAGMA busy_timeout=5000", null).use { it.moveToFirst() }
        db.execSQL("CREATE TABLE IF NOT EXISTS native_recording (id INTEGER PRIMARY KEY CHECK(id=1), walk_id INTEGER NOT NULL REFERENCES recorded_walk(id) ON DELETE CASCADE, active INTEGER NOT NULL, meters REAL NOT NULL DEFAULT 0, last_fix INTEGER NOT NULL DEFAULT 0, alerted INTEGER NOT NULL DEFAULT 0, restarts INTEGER NOT NULL DEFAULT 0, resume_boundary INTEGER NOT NULL DEFAULT 0, manual_interval INTEGER NOT NULL DEFAULT 0)")
    }
    fun state(): MutableMap<String, Any?>? = db.rawQuery(
        "SELECT n.*, w.started_at, w.ended_at, w.trace_metadata, w.status, (SELECT COUNT(*) FROM recorded_point WHERE walk_id=w.id) AS point_count FROM native_recording n JOIN recorded_walk w ON w.id=n.walk_id WHERE n.id=1", null
    ).use { c ->
        if (!c.moveToFirst()) return null
        fun str(key: String) = c.getString(c.getColumnIndexOrThrow(key))
        fun num(key: String) = c.getLong(c.getColumnIndexOrThrow(key))
        val metadata = JSONObject(str("trace_metadata"))
        mutableMapOf("walkId" to num("walk_id"), "active" to (num("active") == 1L),
            "startedAt" to str("started_at"), "endedAt" to str("ended_at"), "status" to str("status"),
            "activity" to metadata.optString("activity", "walk"), "manualInterval" to num("manual_interval"),
            "segments" to (metadata.optJSONArray("segmentStarts") ?: JSONArray()).let { a -> List(a.length()) { a.getInt(it) } },
            "diagnostics" to jsonMap(metadata.optJSONObject("gpsDiagnostics") ?: JSONObject()),
            "meters" to c.getDouble(c.getColumnIndexOrThrow("meters")), "lastFix" to num("last_fix"),
            "alerted" to (num("alerted") == 1L), "resumeBoundary" to (num("resume_boundary") == 1L), "restarts" to num("restarts"), "pointCount" to num("point_count"))
    }
    fun start(activity: String, now: Long, resumeId: Long?, manualInterval: Long = 0): Long = transaction {
        val old = state()
        if (resumeId != null) {
            check(old != null && old["walkId"] == resumeId && old["active"] == true) { "Walk is no longer resumable" }
            db.execSQL("UPDATE recorded_walk SET status='recording', ended_at=NULL, fingerprint=NULL WHERE id=?", arrayOf<Any?>(resumeId))
            db.execSQL("UPDATE native_recording SET resume_boundary=1 WHERE walk_id=?", arrayOf<Any?>(resumeId))
            resumeId
        } else {
            check(old?.get("active") != true) { "A walk is already active" }
            val values = ContentValues().apply {
                put("started_at", iso(now)); put("status", "recording")
                put("trace_metadata", JSONObject().put("activity", activity).toString())
            }
            val id = db.insertOrThrow("recorded_walk", null, values)
            db.execSQL("INSERT OR REPLACE INTO native_recording(id,walk_id,active,manual_interval) VALUES(1,?,1,?)", arrayOf<Any?>(id, manualInterval))
            id
        }
    }
    fun append(id: Long, location: Location, meters: Double, metrics: JSONObject): Boolean = transaction {
        val s = state() ?: return@transaction false
        if (s["walkId"] != id || s["active"] != true || location.time <= s["lastFix"] as Long) return@transaction false
        val position = JSONObject().apply {
            put("latitude", location.latitude); put("longitude", location.longitude); put("timestamp", location.time)
            put("accuracy", location.accuracy.toDouble()); put("altitude", location.altitude)
            put("heading", location.bearing.toDouble()); put("speed", location.speed.toDouble())
            put("altitude_accuracy", if (Build.VERSION.SDK_INT >= 26 && location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else 0.0)
            put("heading_accuracy", if (Build.VERSION.SDK_INT >= 26 && location.hasBearingAccuracy()) location.bearingAccuracyDegrees.toDouble() else 0.0)
            put("speed_accuracy", if (Build.VERSION.SDK_INT >= 26 && location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond.toDouble() else 0.0)
            put("is_mocked", location.isFromMockProvider)
        }
        db.insertOrThrow("recorded_point", null, ContentValues().apply {
            put("walk_id", id); put("seq", s["pointCount"] as Long)
            put("position", position.toString()); put("timestamp", iso(location.time))
        })
        val meta = metadata(id).put("gpsDiagnostics", metrics)
        if (s["resumeBoundary"] == true && s["pointCount"] as Long > 0) {
            val segments = meta.optJSONArray("segmentStarts") ?: JSONArray()
            segments.put(s["pointCount"])
            meta.put("segmentStarts", segments)
        }
        db.execSQL("UPDATE recorded_walk SET fingerprint=NULL, trace_metadata=? WHERE id=?", arrayOf<Any?>(meta.toString(), id))
        db.execSQL("UPDATE native_recording SET meters=?,last_fix=?,resume_boundary=0 WHERE walk_id=? AND active=1", arrayOf<Any?>(meters, location.time, id))
        true
    }
    fun finish(id: Long, now: Long, interrupted: Boolean): Boolean = transaction {
        val s = state() ?: return@transaction false
        if (s["walkId"] != id || s["active"] != true) return@transaction false
        val end = if (interrupted) (s["lastFix"] as Long).takeIf { it > 0 }?.let { iso(it) } ?: s["startedAt"] else iso(now)
        db.execSQL("UPDATE recorded_walk SET status=?,ended_at=?,fingerprint=NULL WHERE id=?", arrayOf<Any?>(if (interrupted) "interrupted" else "completed", end, id))
        db.execSQL("UPDATE native_recording SET active=0 WHERE walk_id=?", arrayOf<Any?>(id))
        true
    }
    fun markAlerted() { db.execSQL("UPDATE native_recording SET alerted=1 WHERE id=1") }
    fun restart() { db.execSQL("UPDATE native_recording SET restarts=restarts+1 WHERE id=1") }
    fun points(id: Long, after: Int): List<Map<String, Any?>> = db.rawQuery(
        "SELECT seq,position FROM recorded_point WHERE walk_id=? AND seq>? ORDER BY seq LIMIT 500", arrayOf(id.toString(), after.toString())
    ).use { c -> buildList { while (c.moveToNext()) add(mapOf("sequence" to c.getInt(0), "position" to jsonMap(JSONObject(c.getString(1))))) } }
    private fun metadata(id: Long): JSONObject = db.rawQuery("SELECT trace_metadata FROM recorded_walk WHERE id=?", arrayOf(id.toString())).use { it.moveToFirst(); JSONObject(it.getString(0)) }
    private fun <T> transaction(block: () -> T): T {
        db.beginTransaction()
        try { return block().also { db.setTransactionSuccessful() } } finally { db.endTransaction() }
    }
    override fun close() = db.close()
    companion object {
        fun iso(time: Long): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(time))
        fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key -> json.opt(key).takeUnless { it == JSONObject.NULL } }
    }
}
