package com.simiono.wanderlust

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSensor
import org.robolectric.shadows.ShadowSensorManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35], manifest=Config.NONE)
class CompassEventsTest {
    class Sink : EventChannel.EventSink {
        val values = mutableListOf<Any?>()
        override fun success(event: Any?) { values.add(event) }
        override fun error(code: String, message: String?, details: Any?) { fail(message) }
        override fun endOfStream() {}
    }
    @Test fun `compass requires a visible activity and listener and unregisters on pause`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val manager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val shadow = shadowOf(manager)
        shadow.addSensor(ShadowSensor.newInstance(Sensor.TYPE_ROTATION_VECTOR))
        val compass = CompassEvents(activity)
        val sink = Sink()
        compass.onListen(null, sink)
        assertFalse(shadow.hasListener(compass))
        compass.resume()
        assertTrue(shadow.hasListener(compass))
        val event = ShadowSensorManager.createSensorEvent(4, Sensor.TYPE_ROTATION_VECTOR)
        event.values[3] = 1f
        event.accuracy = SensorManager.SENSOR_STATUS_ACCURACY_HIGH
        event.timestamp = 1_000_000_000L
        shadow.sendSensorEventToListeners(event)
        val value = sink.values.last() as Map<*, *>
        assertEquals(true, value["available"])
        assertEquals(0.0, value["heading"] as Double, 0.001)
        compass.pause()
        assertFalse(shadow.hasListener(compass))
        compass.resume()
        assertTrue(shadow.hasListener(compass))
        compass.onCancel(null)
        assertFalse(shadow.hasListener(compass))
        compass.close()
    }
    @Test fun `missing sensor reports unavailable without starting work`() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val manager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val shadow = shadowOf(manager)
        manager.getSensorList(Sensor.TYPE_ALL).forEach { shadow.removeSensor(it) }
        val compass = CompassEvents(activity)
        val sink = Sink()
        compass.resume()
        compass.onListen(null, sink)
        assertEquals(false, (sink.values.last() as Map<*, *>)["available"])
        assertFalse(shadow.hasListener(compass))
        compass.close()
    }
}
