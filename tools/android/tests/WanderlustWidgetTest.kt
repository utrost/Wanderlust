package com.simiono.wanderlust

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35])
class WanderlustWidgetTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val manager get() = AppWidgetManager.getInstance(context)
    private fun state(active: Boolean = true, id: Long = 1, meters: Double = 1234.0) = mapOf<String, Any?>("active" to active, "walkId" to id, "meters" to meters)
    @Before fun setup() {
        context.getSharedPreferences("home_widget", Context.MODE_PRIVATE).edit().clear().commit()
        WanderlustWidget.allowNextUpdate()
    }
    @Test fun `widget opens visible app without starting a service or GPS`() {
        val id = shadowOf(manager).createWidget(WanderlustWidget::class.java, R.layout.wanderlust_widget)
        val root = shadowOf(manager).getViewFor(id)
        assertTrue(root.findViewById<View>(R.id.widget_root).performClick())
        val intent = shadowOf(context).nextStartedActivity
        assertEquals(MainActivity::class.java.name, intent.component!!.className)
        assertNull(shadowOf(context).nextStartedService)
        assertFalse(context.getDatabasePath("wanderlust.db").exists())
    }
    @Test fun `recording snapshots are throttled but state changes publish immediately`() {
        val id = shadowOf(manager).createWidget(WanderlustWidget::class.java, R.layout.wanderlust_widget)
        WanderlustWidget.publish(context, state(), true)
        assertEquals(1234.0, WanderlustWidget.read(context)!!.meters, 0.0)
        WanderlustWidget.publish(context, state(meters=1400.0), true)
        assertEquals(1234.0, WanderlustWidget.read(context)!!.meters, 0.0)
        ShadowSystemClock.advanceBy(Duration.ofSeconds(61))
        WanderlustWidget.publish(context, state(meters=1500.0), true)
        assertEquals(1500.0, WanderlustWidget.read(context)!!.meters, 0.0)
        val root = shadowOf(manager).getViewFor(id)
        assertTrue(root.findViewById<TextView>(R.id.widget_status).text.contains("Last recording update"))
        assertTrue(root.findViewById<TextView>(R.id.widget_updated).text.startsWith("Updated "))
        WanderlustWidget.publish(context, state(), false)
        assertEquals("attention", WanderlustWidget.read(context)!!.phase)
        WanderlustWidget.publish(context, state(false), false)
        assertEquals("idle", WanderlustWidget.read(context)!!.phase)
        WanderlustWidget.publish(context, state(id=2), true, true)
        assertEquals("gps", WanderlustWidget.read(context)!!.phase)
    }
    @Test fun `without widgets periodic updates do not rewrite the snapshot`() {
        WanderlustWidget.publish(context, state(), true)
        val initial = WanderlustWidget.read(context)
        ShadowSystemClock.advanceBy(Duration.ofMinutes(2))
        WanderlustWidget.publish(context, state(meters=2000.0), true)
        assertEquals(initial, WanderlustWidget.read(context))
    }
    @Test fun `corrupt or missing snapshot is safe and widget failures do not propagate`() {
        assertNull(WidgetSnapshot.decode(null))
        assertNull(WidgetSnapshot.decode("broken"))
        assertNull(WidgetSnapshot.decode("""{"phase":"unknown","walkId":1,"meters":0,"updatedAt":100}"""))
        assertEquals(0.0, WidgetSnapshot.fromRecording(state(meters=Double.NaN), true, false, 100).meters, 0.0)
        val broken = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = throw IllegalStateException("Storage unavailable")
        }
        WanderlustWidget.publish(broken, state(id=99), true)
        assertNull(WanderlustWidget.read(context))
    }
    @Test fun `a frozen snapshot keeps its original date and never runs an elapsed timer`() {
        val id = shadowOf(manager).createWidget(WanderlustWidget::class.java, R.layout.wanderlust_widget)
        WanderlustWidget.publish(context, state(), true)
        val before = shadowOf(manager).getViewFor(id).findViewById<TextView>(R.id.widget_updated).text.toString()
        ShadowSystemClock.advanceBy(Duration.ofDays(1))
        WanderlustWidget().onUpdate(context, manager, intArrayOf(id))
        val after = shadowOf(manager).getViewFor(id).findViewById<TextView>(R.id.widget_updated).text.toString()
        assertEquals(before, after)
    }
    @Test @Config(qualifiers="w320dp-h640dp") fun `large text remains within a resized card and has complete accessible label`() {
        RuntimeEnvironment.setFontScale(2.0f)
        val id = shadowOf(manager).createWidget(WanderlustWidget::class.java, R.layout.wanderlust_widget)
        WanderlustWidget.publish(context, state(), true)
        val root = shadowOf(manager).getViewFor(id)
        val width = (300 * context.resources.displayMetrics.density).toInt()
        val height = (240 * context.resources.displayMetrics.density).toInt()
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, width, height)
        val last = root.findViewById<TextView>(R.id.widget_updated)
        assertTrue(last.bottom <= height)
        assertTrue(root.findViewById<View>(R.id.widget_root).contentDescription.contains("Open Wanderlust"))
        assertTrue(root.findViewById<View>(R.id.widget_root).contentDescription.contains("Updated"))
    }
}
