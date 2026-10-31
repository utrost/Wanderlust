package com.simiono.wanderlust

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.text.format.DateFormat
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Date

/** A dated snapshot, never a claim that a stopped/frozen process is still alive. */
data class WidgetSnapshot(val phase: String, val walkId: Long, val meters: Double, val updatedAt: Long) {
    fun encode(): String = JSONObject().put("phase", phase).put("walkId", walkId)
        .put("meters", meters).put("updatedAt", updatedAt).toString()
    companion object {
        fun fromRecording(state: Map<String, Any?>?, running: Boolean, gpsPaused: Boolean, now: Long): WidgetSnapshot {
            val active = state?.get("active") == true
            val phase = if (!active) "idle" else if (!running) "attention" else if (gpsPaused) "gps" else "recording"
            val meters = (state?.get("meters") as? Number)?.toDouble()?.takeIf { it.isFinite() && it >= 0 } ?: 0.0
            return WidgetSnapshot(phase, (state?.get("walkId") as? Number)?.toLong() ?: -1, meters, now)
        }
        fun decode(value: String?): WidgetSnapshot? = try {
            value?.let {
                val j = JSONObject(it)
                val phase = j.getString("phase")
                val meters = j.getDouble("meters")
                val updated = j.getLong("updatedAt")
                if (phase !in setOf("idle", "attention", "gps", "recording") || !meters.isFinite() || meters < 0 || updated <= 0) null
                else WidgetSnapshot(phase, j.getLong("walkId"), meters, updated)
            }
        } catch (_: Exception) { null }
    }
}

/** RemoteViews only: no engine, journal connection, location request or timer. */
class WanderlustWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        allowNextUpdate()
        render(context, manager, ids, read(context))
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, intArrayOf(id), read(context))
    }
    companion object {
        private const val PREFS = "home_widget"
        private const val SNAPSHOT = "snapshot"
        private var lastAttempt = Long.MIN_VALUE
        private var lastPhase: String? = null
        private var lastWalk = -1L
        private fun preferences(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        fun read(context: Context): WidgetSnapshot? = WidgetSnapshot.decode(preferences(context).getString(SNAPSHOT, null))
        @Synchronized internal fun allowNextUpdate() { lastAttempt = Long.MIN_VALUE }

        /** Called with data already read by the recorder. A widget failure never fails a walk. */
        @Synchronized fun publish(context: Context, state: Map<String, Any?>?, running: Boolean, gpsPaused: Boolean = false) {
            try {
                val value = WidgetSnapshot.fromRecording(state, running, gpsPaused, System.currentTimeMillis())
                val elapsed = SystemClock.elapsedRealtime()
                val changed = value.phase != lastPhase || value.walkId != lastWalk
                if (!changed && lastAttempt != Long.MIN_VALUE && elapsed - lastAttempt in 0 until 60000) return
                lastAttempt = elapsed
                lastPhase = value.phase
                lastWalk = value.walkId
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, WanderlustWidget::class.java))
                // Keep state transitions for newly placed widgets, but no periodic
                // disk writes when nobody has installed a widget.
                if (!changed && ids.isEmpty()) return
                preferences(context).edit().putString(SNAPSHOT, value.encode()).apply()
                render(context, manager, ids, value)
            } catch (e: Exception) {
                android.util.Log.w("WanderlustWidget", "Widget update unavailable", e)
            }
        }

        internal fun render(context: Context, manager: AppWidgetManager, ids: IntArray, value: WidgetSnapshot?) {
            if (ids.isEmpty()) return
            val text = when (value?.phase) {
                "recording" -> context.getString(R.string.widget_recording, value.meters / 1000)
                "gps" -> context.getString(R.string.widget_gps, value.meters / 1000)
                "attention" -> context.getString(R.string.widget_attention)
                else -> context.getString(R.string.widget_idle)
            }
            val time = value?.let {
                // Include the date so a frozen widget cannot look like today's update.
                DateFormat.getDateFormat(context).format(Date(it.updatedAt)) + " " +
                    DateFormat.getTimeFormat(context).format(Date(it.updatedAt))
            }
            val caption = if (time == null) context.getString(R.string.widget_open)
                else context.getString(R.string.widget_updated, time)
            val intent = PendingIntent.getActivity(context, 5413,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val views = RemoteViews(context.packageName, R.layout.wanderlust_widget).apply {
                setTextViewText(R.id.widget_status, text)
                setTextViewText(R.id.widget_updated, caption)
                setContentDescription(R.id.widget_root, context.getString(R.string.widget_open) + ". " + text + ". " + caption)
                setOnClickPendingIntent(R.id.widget_root, intent)
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
