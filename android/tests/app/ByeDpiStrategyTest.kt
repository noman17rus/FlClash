package com.follow.clash

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ByeDpiStrategyTest {
    @Test fun handlesBundledStrategiesAndSni() {
        val entries = ByeDpiStrategy.catalog(File("src/main/assets/byedpi/proxytest_strategies.list").readText())
        assertTrue(entries.isNotEmpty())
        assertEquals(listOf("-n", "google.com", "-d", "1"), ByeDpiStrategy.arguments("-n \"{sni}\" --disorder=1"))
    }

    @Test fun rejectsCatalogsThatChangeListenerOrAccessFiles() {
        for (entry in listOf("-p1080", "--ip=0.0.0.0", "-Si0.0.0.0", "-H /data/x", "-d1\n<html>", "-n \"open")) {
            assertThrows(IllegalArgumentException::class.java) { ByeDpiStrategy.catalog(entry) }
        }
        assertEquals(listOf("-d1", "-o2"), ByeDpiStrategy.catalog("-d1\r\n# comment\n-o2\n-d1"))
    }
}
