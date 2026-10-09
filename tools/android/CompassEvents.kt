package com.simiono.wanderlust

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/** UI-only magnetic heading. Never runs with the activity paused. */
class CompassEvents(private val activity: Activity) : EventChannel.StreamHandler, SensorEventListener {
    private val manager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private var sink: EventChannel.EventSink? = null
    private var resumed = false
    private var registered = false
    private var last = 0L
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        start()
    }
    override fun onCancel(arguments: Any?) { stop(); sink = null }
    fun resume() { resumed = true; start() }
    fun pause() { resumed = false; stop() }
    fun close() { pause(); sink = null }
    private fun start() {
        if (sink == null || !resumed || registered) return
        last = 0L
        registered = sensor != null && manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
        if (!registered) sink?.success(mapOf("available" to false))
    }
    private fun stop() { manager.unregisterListener(this); registered = false }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    override fun onSensorChanged(event: SensorEvent) {
        if (!registered || event.timestamp - last < 100_000_000L) return
        last = event.timestamp
        val matrix = FloatArray(9)
        val rotated = FloatArray(9)
        val orientation = FloatArray(3)
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        @Suppress("DEPRECATION")
        val rotation = activity.windowManager.defaultDisplay.rotation
        val axes = when (rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(matrix, axes.first, axes.second, rotated)
        SensorManager.getOrientation(rotated, orientation)
        val degrees = (Math.toDegrees(orientation[0].toDouble()) + 360.0) % 360.0
        sink?.success(mapOf("available" to true, "heading" to degrees, "accuracy" to event.accuracy))
    }
}
