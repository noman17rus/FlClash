package com.follow.clash

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Test

class ByeDpiRoutesTest {
    @Test fun showsActualVideoChainEvenWhenNewConnectionsUseADifferentRoute() {
        val proxies = JsonParser.parseString("""{
            "YouTube [1]":{"now":"VLESS / WDTT [1]"},
            "VLESS / WDTT [1]":{"now":"Auto [1]"},
            "Auto [1]":{"now":"VLESS [1]"},
            "VLESS [1]":{"now":"node"}
        }""").asJsonObject
        val entries = JsonParser.parseString("""[
            {"metadata":{"host":"www.youtube.com"},"chains":["node","VLESS [1]","YouTube [1]"],"download":500},
            {"metadata":{"host":"rr1.googlevideo.com"},"chains":["ByeDPI [1]","YouTube [1]"],"download":10000},
            {"metadata":{"host":"example.com"},"chains":["WDTT [1]"],"download":9000},
            {"metadata":{"host":"i.ytimg.com"},"chains":["WDTT [1]"],"download":200}
        ]""").asJsonArray.map { it.asJsonObject }
        val status = ByeDpiRoutes.describe(proxies, entries, "YouTube [1]", "[1]")
        assertEquals("VLESS", status["next"])
        val connections = (status["connections"] as List<*>).map { it as Map<*, *> }
        assertEquals(3, connections.size)
        assertEquals("ByeDPI", connections.first()["route"])
        assertEquals(true, connections.first()["video"])
        assertEquals(10000L, connections.first()["download"])
        assertEquals(setOf("ByeDPI", "VLESS", "WDTT"), connections.map { it["route"] }.toSet())
    }
}
