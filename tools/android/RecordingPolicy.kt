package com.simiono.wanderlust

import kotlin.math.*

/** Pure movement policy. Raw fixes are retained separately from display distance. */
class RecordingPolicy(val cycling: Boolean, val started: Long, initialMeters: Double = 0.0, val manualInterval: Long? = null, val automatic: Boolean = false) {
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
    private var prior: Fix? = null
    private var fastUntil = 0L

    fun interval(now: Long): Long = when {
        manualInterval != null -> manualInterval
        now - started < 20000 || (!fresh && now - started < 45000) -> 1000
        stationary -> 15000
        now < turningUntil -> 1000
        automatic && now < fastUntil -> 2000
        cycling && !automatic -> 2000
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
        var limit = if (!automatic && cycling) 15.0 else 3.0
        if (automatic && previous != null) {
            val dt = (p.time - previous.time) / 1000.0
            val v = if (dt > 0 && dt <= 30) distance(previous, p) / dt else 0.0
            val reported = p.speed
            val before = prior
            val oldDt = if (before != null) (previous.time-before.time)/1000.0 else 0.0
            val oldSpeed = if (before != null && oldDt > 0 && oldDt <= 30) distance(before, previous)/oldDt else 0.0
            val aligned = before != null && (previous.lat-before.lat)*(p.lat-previous.lat) +
                (previous.lon-before.lon)*(p.lon-previous.lon)*cos(Math.toRadians(p.lat)).pow(2) > 0
            if (reported != null && reported >= 0.7 && abs(reported-v) <= max(2.0,reported*0.5)) {
                limit = (reported*1.8+2).coerceIn(3.0,70.0)
            } else if (oldSpeed > 2.5 && v >= oldSpeed*0.4 && v <= oldSpeed*2.5 && aligned) {
                limit = (max(v,oldSpeed)*1.8+2).coerceIn(3.0,70.0)
            }
            if (limit > 5) fastUntil = now + 15000
        }
        prior = previous
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
            if (seconds > 0 && d / seconds <= limit &&
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
