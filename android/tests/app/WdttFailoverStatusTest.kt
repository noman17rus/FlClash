package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WdttFailoverStatusTest {
    @Test
    fun `ByeDPI is unavailable only after a failed VLESS check on the current cellular network`() {
        val status = WdttFailoverStatus { 0L }
        assertFalse(status.byeDpiUnavailable(true, 1))
        status.primaryMeasured(false, 1)
        assertTrue(status.byeDpiUnavailable(true, 1))
        assertFalse(status.byeDpiUnavailable(false, 1))
        assertFalse(status.byeDpiUnavailable(true, 2))
        status.primaryMeasured(true, 1)
        assertFalse(status.byeDpiUnavailable(true, 1))
        status.update("VLESS / WDTT [1]", "backup", "WDTT")
        status.primaryMeasured(false, 1, "VLESS / WDTT [1]")
        assertTrue(status.byeDpiUnavailable(true, 1))
        status.update("VLESS / WDTT [2]", "manualWdtt", "WDTT")
        assertFalse(status.byeDpiUnavailable(true, 1))
    }

    @Test
    fun `recovery updates preserve route transition time and suppress duplicate events`() {
        var now = 100L
        val status = WdttFailoverStatus { now }
        status.update("VLESS / WDTT [1]", "backup", "WDTT")
        now = 200L
        status.update(phase = "backup")
        status.update(phase = "recovering")
        val snapshot = status.snapshot()
        assertEquals(100L, snapshot["switchedAt"])
        assertEquals("WDTT", snapshot["route"])
        assertEquals(2, (snapshot["events"] as List<*>).size)
        status.update(phase = "primary", route = "VLESS")
        assertEquals(200L, status.snapshot()["switchedAt"])
    }

    @Test
    fun `history keeps eight newest immutable entries`() {
        var now = 0L
        val status = WdttFailoverStatus { now++ }
        repeat(12) { status.update(phase = if (it % 2 == 0) "offline" else "checking") }
        val before = status.snapshot()
        val events = before["events"] as List<*>
        assertEquals(8, events.size)
        assertEquals(11L, (events.first() as Map<*, *>)["time"])
        status.update(phase = "backup", route = "WDTT")
        assertEquals(11L, (events.first() as Map<*, *>)["time"])
    }
}
