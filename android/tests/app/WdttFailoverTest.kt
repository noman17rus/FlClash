package com.follow.clash

import com.follow.clash.service.UnderlyingNetworkState
import com.google.gson.JsonNull
import com.google.gson.JsonParser
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WdttFailoverTest {
    private class Fixture {
        var now = 0L
        var network = UnderlyingNetworkState(1, 1)
        var mode = "Auto [1]"
        var selected = "VLESS [1]"
        var healthy = false
        var measured = true
        var ready = true
        var running = false
        var probes = 0
        var restarts = 0
        var closed = 0
        var duringProbe: () -> Unit = {}
        val monitor = WdttFailover(
            reconcile = { needed, restart ->
                running = needed
                if (restart) restarts++
                ready && needed
            },
            networkState = { network },
            clock = { now },
            rpc = { method, arguments ->
                when (method) {
                    "proxy.list" -> JsonParser.parseString("""{"proxies":{
                        "VLESS / WDTT [1]":{"now":"$mode"},
                        "VLESS [1]":{"all":["node"],"testUrl":"https://example.com/check"},
                        "Auto [1]":{"now":"$selected"}}}""")
                    "proxy.testDelay" -> {
                        assertEquals("https://example.com/check", arguments["test-url"])
                        probes++
                        duringProbe()
                        if (measured) JsonParser.parseString("""{"value":${if (healthy) 100 else -1}}""")
                        else JsonNull.INSTANCE
                    }
                    "proxy.select" -> {
                        val next = arguments["proxy-name"] as String
                        val changed = selected != next
                        selected = next
                        JsonParser.parseString("""{"changed":$changed}""")
                    }
                    "connection.closeAll" -> { closed++; JsonNull.INSTANCE }
                    else -> error(method)
                }
            },
        )

        suspend fun tick(time: Long) { now = time; monitor.tick() }
        suspend fun fail() { tick(0); tick(4_000); tick(9_000); tick(14_000) }
    }

    @Test
    fun `backup stays off until primary failure is confirmed and backup is ready`() = runTest {
        val f = Fixture()
        f.ready = false
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        assertFalse(f.running)
        f.tick(14_000)
        assertTrue(f.running)
        assertEquals("VLESS [1]", f.selected)
        f.ready = true
        f.tick(16_000)
        assertEquals("WDTT [1]", f.selected)
        assertEquals(1, f.closed)
    }

    @Test
    fun `stable primary recovery stops backup and closes old traffic`() = runTest {
        val f = Fixture()
        f.fail()
        f.healthy = true
        f.tick(44_000)
        assertTrue(f.running)
        f.tick(49_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
        assertEquals(2, f.closed)
    }

    @Test
    fun `offline pauses probes and stops backup only after a grace period`() = runTest {
        val f = Fixture()
        f.fail()
        val probes = f.probes
        f.network = UnderlyingNetworkState(null, 2)
        f.tick(15_000)
        f.tick(20_000)
        assertTrue(f.running)
        f.tick(30_000)
        assertFalse(f.running)
        assertEquals(probes, f.probes)
        f.network = UnderlyingNetworkState(2, 3)
        f.tick(31_000)
        assertFalse(f.running)
        f.tick(35_000)
        assertTrue(f.running)
        assertEquals(1, f.restarts)
    }

    @Test
    fun `probe from an old network cannot start backup`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.duringProbe = { f.network = UnderlyingNetworkState(2, 2) }
        f.tick(14_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `unanswered measurement is not evidence to start backup`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.measured = false
        assertTrue(runCatching { f.tick(14_000) }.isFailure)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `manual override during probe discards automatic failover`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.duringProbe = { f.mode = "VLESS [1]" }
        f.tick(14_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `WiFi to cellular handover restarts backup once after stabilization`() = runTest {
        val f = Fixture()
        f.fail()
        f.network = UnderlyingNetworkState(2, 2)
        f.tick(15_000)
        f.tick(17_000)
        assertEquals(0, f.restarts)
        f.tick(19_000)
        f.tick(21_000)
        assertTrue(f.running)
        assertEquals(1, f.restarts)
    }

    @Test
    fun `manual VLESS stops backup and manual WDTT starts it without probing`() = runTest {
        val f = Fixture()
        f.fail()
        val probes = f.probes
        f.mode = "VLESS [1]"
        f.tick(16_000)
        assertFalse(f.running)
        f.mode = "WDTT [1]"
        f.tick(20_000)
        assertTrue(f.running)
        assertEquals(probes, f.probes)
    }
}
