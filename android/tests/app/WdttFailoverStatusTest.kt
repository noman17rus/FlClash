package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Test

class WdttFailoverStatusTest {
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
