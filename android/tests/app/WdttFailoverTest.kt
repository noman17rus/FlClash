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
        var connectionMode = ConnectionMode.balanced
        var network = UnderlyingNetworkState(1, 1)
        var mode = "Auto [1]"
        var selected = "VLESS [1]"
        var healthy = false
        var measured = true
        var ready = true
        var running = false
        var probes = 0
        var testUrl = "https://example.com/check"
        val probeRequests = mutableListOf<Pair<String, String>>()
        var probeResult: ((String, String) -> Int?)? = null
        var restarts = 0
        var selectionRefused = false
        var duringProbe: () -> Unit = {}
        val monitor = WdttFailover(
            connectionMode = { connectionMode },
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
                        "VLESS transport [1]":{"all":["node"],"testUrl":"$testUrl"},
                        "Auto [1]":{"now":"$selected"}}}""")
                    "proxy.testDelay" -> {
                        val name = arguments["proxy-name"] as String
                        val url = arguments["test-url"] as String
                        probeRequests += name to url
                        probes++
                        duringProbe()
                        val value = when {
                            probeResult != null -> probeResult!!.invoke(name, url)
                            measured -> if (healthy) 100 else -1
                            else -> null
                        }
                        if (value != null) JsonParser.parseString("""{"value":$value}""") else JsonNull.INSTANCE
                    }
                    "proxy.select" -> {
                        val next = arguments["proxy-name"] as String
                        val changed = selected != next
                        if (selectionRefused) JsonParser.parseString("""{"message":"refused"}""")
                        else {
                            selected = next
                            JsonParser.parseString("""{"changed":$changed}""")
                        }
                    }
                    else -> error(method)
                }
            },
        )

        suspend fun tick(time: Long) { now = time; monitor.tick() }
        suspend fun fail() { tick(0); tick(4_000); tick(9_000); tick(14_000) }
    }

    @Test
    fun `mode changes reschedule checks without restarting the tunnel`() = runTest {
        val f = Fixture()
        f.healthy = true
        f.tick(0)
        f.tick(4_000)
        val probes = f.probes
        f.connectionMode = ConnectionMode.economical
        f.tick(5_000)
        f.tick(9_000)
        assertTrue(f.probes > probes)
        val economicalProbes = f.probes
        f.tick(68_999)
        assertEquals(economicalProbes, f.probes)
        f.tick(69_000)
        assertTrue(f.probes > economicalProbes)
        f.connectionMode = ConnectionMode.fastRecovery
        f.tick(70_000)
        f.tick(74_000)
        val fastProbes = f.probes
        f.tick(78_999)
        assertEquals(fastProbes, f.probes)
        f.tick(79_000)
        assertTrue(f.probes > fastProbes)
        assertEquals(0, f.restarts)
    }

    @Test
    fun `mode change preserves an active backup`() = runTest {
        val f = Fixture()
        f.fail()
        f.connectionMode = ConnectionMode.economical
        f.tick(15_000)
        f.tick(19_000)
        assertTrue(f.running)
        assertEquals("WDTT [1]", f.selected)
        assertEquals(0, f.restarts)
    }

    @Test
    fun `healthy original endpoint needs no alternate probes`() = runTest {
        val f = Fixture()
        f.healthy = true
        f.tick(0)
        f.tick(4_000)
        assertEquals(listOf("node" to f.testUrl), f.probeRequests)
        assertFalse(f.running)
    }

    @Test
    fun `one reachable alternate endpoint keeps the actual VLESS route active`() = runTest {
        for (endpoint in listOf(
            "https://www.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
            "https://www.apple.com/library/test/success.html",
        )) {
            val f = Fixture()
            f.probeResult = { name, url -> if (name == "VLESS transport [1]" && url == endpoint) 100 else -1 }
            f.fail()
            assertFalse(f.running)
            assertEquals("VLESS [1]", f.selected)
            assertTrue(f.probeRequests.any { it == ("VLESS transport [1]" to endpoint) })
            assertTrue(f.probeRequests.filter { it.second != f.testUrl }.all { it.first == "VLESS transport [1]" })
        }
    }

    @Test
    fun `alternate endpoint can confirm recovery from backup`() = runTest {
        val f = Fixture()
        f.fail()
        f.probeResult = { _, url -> if (url == "https://cp.cloudflare.com/generate_204") 100 else -1 }
        f.tick(44_000)
        assertTrue(f.running)
        f.tick(49_000)
        assertTrue(f.running)
        for (time in 54_000L..74_000L step 5_000) f.tick(time)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `missing measurement does not hide a successful alternate endpoint`() = runTest {
        val f = Fixture()
        f.probeResult = { _, url -> if (url == "https://cp.cloudflare.com/generate_204") 100 else null }
        f.fail()
        assertFalse(f.running)
    }

    @Test
    fun `missing alternate measurement is not a confirmed outage`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.probeResult = { _, url -> if (url == "https://cp.cloudflare.com/generate_204") null else -1 }
        assertTrue(runCatching { f.tick(14_000) }.isFailure)
        assertFalse(f.running)
    }

    @Test
    fun `configured default endpoint is not probed twice`() = runTest {
        val f = Fixture()
        f.testUrl = "https://www.gstatic.com/generate_204"
        f.tick(0)
        f.tick(4_000)
        assertEquals(3, f.probes)
        assertEquals(3, f.probeRequests.map { it.second }.distinct().size)
    }

    @Test
    fun `network change during alternate probes discards a healthy result`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.probeResult = { name, _ ->
            if (name == "VLESS transport [1]") {
                f.network = UnderlyingNetworkState(2, 2)
                100
            } else -1
        }
        f.tick(14_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `manual override during alternate probes wins over automatic failover`() = runTest {
        val f = Fixture()
        f.tick(0)
        f.tick(4_000)
        f.tick(9_000)
        f.probeResult = { name, _ ->
            if (name == "VLESS transport [1]") f.mode = "VLESS [1]"
            -1
        }
        f.tick(14_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
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
    }

    @Test
    fun `stable primary recovery stops backup`() = runTest {
        val f = Fixture()
        f.fail()
        f.healthy = true
        f.tick(44_000)
        assertTrue(f.running)
        f.tick(49_000)
        assertTrue(f.running)
        for (time in 54_000L..69_000L step 5_000) {
            f.tick(time)
            assertTrue(f.running)
        }
        f.tick(74_000)
        assertFalse(f.running)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `refused selection preserves the current route`() = runTest {
        val f = Fixture()
        f.selectionRefused = true
        assertTrue(runCatching { f.fail() }.isFailure)
        assertEquals("VLESS [1]", f.selected)
    }

    @Test
    fun `unanswered recovery probe resets the stability window`() = runTest {
        val f = Fixture()
        f.fail()
        f.healthy = true
        f.tick(44_000)
        f.measured = false
        assertTrue(runCatching { f.tick(49_000) }.isFailure)
        f.measured = true
        for (time in 54_000L..79_000L step 5_000) {
            f.tick(time)
            assertTrue(f.running)
        }
        f.tick(84_000)
        assertFalse(f.running)
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

    @Test
    fun `status follows fallback recovery and manual selection`() = runTest {
        val f = Fixture()
        f.fail()
        assertEquals("backup", f.monitor.status.snapshot()["phase"])
        assertEquals("WDTT", f.monitor.status.snapshot()["route"])
        f.healthy = true
        f.tick(44_000)
        assertEquals("recovering", f.monitor.status.snapshot()["phase"])
        f.tick(59_000)
        f.tick(74_000)
        assertEquals("primary", f.monitor.status.snapshot()["phase"])
        assertEquals("VLESS", f.monitor.status.snapshot()["route"])
        f.mode = "WDTT [1]"
        f.tick(76_000)
        assertEquals("manualWdtt", f.monitor.status.snapshot()["phase"])
    }

    @Test
    fun `unready backup does not claim a completed switch`() = runTest {
        val f = Fixture()
        f.ready = false
        f.fail()
        assertEquals("starting", f.monitor.status.snapshot()["phase"])
        assertEquals(null, f.monitor.status.snapshot()["route"])
        f.ready = true
        f.tick(16_000)
        assertEquals("backup", f.monitor.status.snapshot()["phase"])
        f.network = UnderlyingNetworkState(null, 2)
        f.tick(18_000)
        assertEquals("offline", f.monitor.status.snapshot()["phase"])
    }
}
