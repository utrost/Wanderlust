package com.simiono.wanderlust

import kotlin.math.*

/** Pure movement policy. Raw fixes are retained separately from display distance. */
class RecordingPolicy(val cycling: Boolean, val started: Long, initialMeters: Double = 0.0, val manualInterval: Long? = null) {
    data class Fix(val lat: Double, val lon: Double, val accuracy: Double, val time: Long,
                   val speed: Double? = null, val bearing: Double? = null)
    var meters = initialMeters
        private set
    var stationary = false
        private set
    private var anchor: Fix? = null
    private var resting: Fix? = null
    private var last: Fix? = null
    private var movingAt = started
    private var turningUntil = 0L
    private var fresh = false

    fun interval(now: Long): Long = when {
        manualInterval != null -> manualInterval
        now - started < 20000 || (!fresh && now - started < 45000) -> 1000
        stationary -> 15000
        now < turningUntil -> 1000
        cycling -> 2000
        else -> 3000
    }

    fun motion(now: Long) { stationary = false; movingAt = now; resting = null }

    fun add(p: Fix, now: Long) {
        if (last != null && p.time <= last!!.time) return
        fresh = true
        if (p.accuracy > 25 || !p.accuracy.isFinite() || p.accuracy < 0) {
            anchor = null; resting = null; stationary = false; last = p
            return
        }
        val previous = last
        if (previous != null && p.time - previous.time > 45000) {
            anchor = null; resting = null; stationary = false; movingAt = now
        }
        val r = resting
        val movementRadius = max(8.0, min(20.0, p.accuracy * 1.25))
        val moving = (p.speed ?: 0.0) >= 0.7 || (r != null && distance(r, p) > movementRadius)
        if (moving) {
            stationary = false; movingAt = now; resting = p
        } else {
            if (r == null) { resting = p; movingAt = now }
            if (now - movingAt >= 60000) stationary = true
        }
        if (moving && previous?.bearing != null && p.bearing != null) {
            val turn = abs((p.bearing - previous.bearing + 540) % 360 - 180)
            if (turn >= 25) turningUntil = now + 10000
        }
        val a = anchor
        if (a == null) {
            anchor = p
        } else if (stationary) {
            anchor = p
        } else if ((p.speed == null || p.speed < 0.3) && !moving) {
            // Keep the anchor while position confirms whether zero-speed readings
            // are a rest stop or slow movement. A device can under-report speed.
        } else {
            val d = distance(a, p)
            val seconds = (p.time - a.time) / 1000.0
            if (seconds > 0 && d / seconds <= (if (cycling) 15 else 3) &&
                d >= max(3.0, min(8.0, p.accuracy * 0.4))) {
                meters += d; anchor = p
            }
        }
        last = p
    }

    companion object {
        fun distance(a: Fix, b: Fix): Double {
            val lat = Math.toRadians(b.lat - a.lat)
            val lon = Math.toRadians(b.lon - a.lon)
            val h = sin(lat / 2).pow(2) + cos(Math.toRadians(a.lat)) *
                cos(Math.toRadians(b.lat)) * sin(lon / 2).pow(2)
            return 12742000 * asin(sqrt(h.coerceIn(0.0, 1.0)))
        }
    }
}
