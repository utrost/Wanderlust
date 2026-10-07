package com.simiono.wanderlust

import org.junit.Assert.*
import org.junit.Test

class RecordingPolicyTest {
    private fun fix(seconds: Int, meters: Double = 0.0, speed: Double? = null, bearing: Double? = null, accuracy: Double = 5.0) =
        RecordingPolicy.Fix(53.0 + meters/111195, 8.8, accuracy, seconds*1000L, speed, bearing)
    @Test fun `fast acquisition settles to walking and cycling rates`() {
        val walk = RecordingPolicy(false, 0)
        assertEquals(1000L, walk.interval(0))
        walk.add(fix(1), 1000)
        assertEquals(3000L, walk.interval(25000))
        assertEquals(2000L, RecordingPolicy(true, 0).interval(60000))
        assertEquals(3000L, RecordingPolicy(false, 0).interval(60000))
    }
    @Test fun `cafe drift adds no distance and movement wakes sampling`() {
        val policy = RecordingPolicy(false, 0)
        for (s in 1..150 step 3) policy.add(fix(s, (s%4).toDouble(), 0.0), s*1000L)
        assertTrue(policy.stationary)
        assertEquals(0.0, policy.meters, 0.01)
        assertEquals(15000L, policy.interval(150000))
        policy.motion(151000)
        assertFalse(policy.stationary)
        assertEquals(3000L, policy.interval(151000))
        for (s in 153..180 step 3) policy.add(fix(s, (s-150).toDouble(), 1.0), s*1000L)
        assertTrue(policy.meters > 20)
    }
    @Test fun `clear coordinate movement counts even if provider speed is zero`() {
        val policy = RecordingPolicy(false, 0)
        for (s in 0..24 step 4) policy.add(fix(s, s.toDouble(), 0.0), s*1000L)
        assertTrue(policy.meters >= 20)
        assertTrue(policy.meters <= 25)
        assertFalse(policy.stationary)
    }
    @Test fun `stationary jitter without provider speed does not add distance`() {
        val policy = RecordingPolicy(false, 0)
        for (s in 0..180 step 3) policy.add(fix(s, (s%5).toDouble()), s*1000L)
        assertEquals(0.0, policy.meters, 0.01)
        assertTrue(policy.stationary)
    }
    @Test fun `continuous slow movement is not mistaken for a GPS outage`() {
        val policy = RecordingPolicy(false, 0)
        for (s in 0..180 step 3) policy.add(fix(s, s*0.2), s*1000L)
        assertTrue(policy.meters >= 30)
        assertTrue(policy.meters <= 36.1)
    }
    @Test fun `manual cadence remains explicitly selected`() {
        val policy = RecordingPolicy(false, 0, manualInterval=10000)
        for (s in 1..150 step 3) policy.add(fix(s, 0.0, 0.0), s*1000L)
        assertTrue(policy.stationary)
        assertEquals(10000L, policy.interval(160000))
    }
    @Test fun `walking turns temporarily increase sampling`() {
        val policy = RecordingPolicy(false, 0)
        policy.add(fix(30, 0.0, 1.2, 0.0), 30000)
        policy.add(fix(33, 4.0, 1.2, 90.0), 33000)
        assertEquals(1000L, policy.interval(33000))
        assertEquals(3000L, policy.interval(45000))
    }
    @Test fun `outages spikes and poor accuracy do not invent distance`() {
        val policy = RecordingPolicy(false, 0, 100.0)
        policy.add(fix(1), 1000)
        policy.add(fix(2, 1000.0), 2000)
        assertEquals(100.0, policy.meters, 0.01)
        policy.add(fix(90, 2000.0), 90000)
        policy.add(fix(93, 2050.0, accuracy=100.0), 93000)
        policy.add(fix(96, 2004.0), 96000)
        assertEquals(100.0, policy.meters, 0.01)
    }
}
