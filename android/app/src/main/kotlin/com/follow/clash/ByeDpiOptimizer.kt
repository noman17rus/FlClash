package com.follow.clash

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

internal data class ByeDpiMeasurement(val youtube: Long?, val google: Long?)

internal class ByeDpiOptimizer(private val probe: suspend (String) -> ByeDpiMeasurement) {
    private data class Candidate(val strategy: String, val samples: List<ByeDpiMeasurement>) {
        val youtubeWorks get() = samples.all { it.youtube != null }
        val googleSuccesses get() = samples.count { it.google != null }
        val delay get() = samples.sumOf { (it.youtube ?: 0) + (it.google ?: 0) } / samples.size
    }

    private val ranking = compareByDescending<Candidate> { it.youtubeWorks }
        .thenByDescending { it.googleSuccesses }
        .thenBy { it.delay }

    suspend fun select(strategies: List<String>, current: String): String? {
        suspend fun measure(line: String): ByeDpiMeasurement {
            currentCoroutineContext().ensureActive()
            return try {
                probe(line)
            } catch (error: CancellationException) {
                throw error
            } catch (error: IllegalStateException) {
                if (error.message == "NETWORK_CHANGED") throw error
                ByeDpiMeasurement(null, null)
            } catch (_: Exception) {
                ByeDpiMeasurement(null, null)
            }
        }

        val candidates = (listOf(current) + strategies).distinct().map { line ->
            Candidate(line, listOf(measure(line)))
        }
        val finalists = candidates.filter { it.youtubeWorks }.sortedWith(ranking).take(3).toMutableList()
        candidates.first().takeIf { it.youtubeWorks && it !in finalists }?.let(finalists::add)
        val confirmed = finalists.map { candidate ->
            candidate.copy(samples = candidate.samples + List(2) { measure(candidate.strategy) })
        }
        return confirmed.filter { it.youtubeWorks }.sortedWith(ranking).firstOrNull()?.strategy
    }
}

internal object ByeDpiDailySchedule {
    const val INTERVAL = 86_400_000L

    fun remaining(now: Long, attemptedAt: Long): Long {
        if (attemptedAt == 0L) return 0
        val elapsed = now - attemptedAt
        return if (elapsed in 0 until INTERVAL) INTERVAL - elapsed else 0
    }
}
