package com.follow.clash

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ByeDpiOptimizerTest {
    @Test fun prefersReliableYoutubeThenGoogleThenDelay() = runTest {
        val measured = mutableListOf<String>()
        val results = mapOf(
            "current" to ByeDpiMeasurement(150, 100),
            "googleOnly" to ByeDpiMeasurement(null, 1),
            "youtubeOnly" to ByeDpiMeasurement(1, null),
            "fast" to ByeDpiMeasurement(50, 40),
        )
        val optimizer = ByeDpiOptimizer { line -> measured.add(line); results.getValue(line) }
        assertEquals("fast", optimizer.select(results.keys.toList(), "current"))
        assertEquals(3, measured.count { it == "fast" })
        assertEquals(3, measured.count { it == "current" })
        assertEquals(1, measured.count { it == "googleOnly" })
    }

    @Test fun retainsWorkingCurrentWhenFastCandidateFailsConfirmation() = runTest {
        val calls = mutableMapOf<String, Int>()
        val optimizer = ByeDpiOptimizer { line ->
            val count = calls.getOrDefault(line, 0) + 1
            calls[line] = count
            when {
                line == "current" -> ByeDpiMeasurement(100, 100)
                count == 1 -> ByeDpiMeasurement(1, 1)
                else -> ByeDpiMeasurement(null, 1)
            }
        }
        assertEquals("current", optimizer.select(listOf("unstable"), "current"))
    }

    @Test fun doesNotReplaceCurrentWhenNoStrategyReachesYoutube() = runTest {
        val optimizer = ByeDpiOptimizer { ByeDpiMeasurement(null, 1) }
        assertNull(optimizer.select(listOf("one", "two"), "current"))
    }

    @Test fun testsCurrentEvenWhenMissingFromCatalogAndKeepsItOnTies() = runTest {
        val measured = mutableListOf<String>()
        val optimizer = ByeDpiOptimizer { line -> measured.add(line); ByeDpiMeasurement(50, 50) }
        assertEquals("current", optimizer.select(listOf("one", "one"), "current"))
        assertEquals(3, measured.count { it == "current" })
        assertEquals(3, measured.count { it == "one" })
    }

    @Test fun failedCandidatesDoNotAbortOtherChecks() = runTest {
        val optimizer = ByeDpiOptimizer { line ->
            if (line == "broken") error("process exited")
            ByeDpiMeasurement(50, 50)
        }
        assertEquals("current", optimizer.select(listOf("broken"), "current"))
    }

    @Test fun confirmsCurrentOutsideTopThreeBeforeReplacingIt() = runTest {
        val calls = mutableMapOf<String, Int>()
        val optimizer = ByeDpiOptimizer { line ->
            val count = calls.getOrDefault(line, 0) + 1
            calls[line] = count
            val delay = when {
                line == "current" && count == 1 -> 500L
                line == "current" -> 1L
                count == 1 -> 100L
                else -> 250L
            }
            ByeDpiMeasurement(delay, delay)
        }
        assertEquals("current", optimizer.select(listOf("one", "two", "three"), "current"))
        assertEquals(3, calls["current"])
    }

    @Test fun networkChangeAndCancellationAbortWithoutApplyingResult() = runTest {
        for (failure in listOf(IllegalStateException("NETWORK_CHANGED"), CancellationException())) {
            val measured = mutableListOf<String>()
            val optimizer = ByeDpiOptimizer { line -> measured.add(line); throw failure }
            var caught: Exception? = null
            try { optimizer.select(listOf("one"), "current") } catch (error: Exception) { caught = error }
            assertTrue(caught === failure)
            assertEquals(listOf("current"), measured)
        }
    }

    @Test fun persistedAttemptEnforcesOneScanPerDayAcrossRestarts() {
        val day = ByeDpiDailySchedule.INTERVAL
        assertEquals(0L, ByeDpiDailySchedule.remaining(1000, 0))
        assertEquals(day, ByeDpiDailySchedule.remaining(1000, 1000))
        assertEquals(day - 500, ByeDpiDailySchedule.remaining(1500, 1000))
        assertEquals(0L, ByeDpiDailySchedule.remaining(1000 + day, 1000))
        assertEquals(0L, ByeDpiDailySchedule.remaining(999, 1000))
    }
}
