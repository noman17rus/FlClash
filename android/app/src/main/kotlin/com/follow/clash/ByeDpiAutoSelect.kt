package com.follow.clash

import android.content.Context
import com.follow.clash.common.GlobalState
import com.follow.clash.service.NetworkObserver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

internal object ByeDpiAutoSelect {
    private val selectionLock = Mutex()
    private val manualRevision = MutableStateFlow(0L)
    private data class Selection(val configured: String, val best: String)
    private val prefs by lazy {
        GlobalState.application.getSharedPreferences("byedpi_auto_selection", Context.MODE_PRIVATE)
    }
    private val selected by lazy {
        val configured = prefs.getString("configured", null)
        val best = prefs.getString("best", null)
        MutableStateFlow(if (configured != null && best != null) Selection(configured, best) else null)
    }

    val effectiveStrategy get() = combine(ByeDpi.strategy, selected) { configured, selection ->
        if (selection?.configured == configured) selection?.best else configured
    }

    suspend fun manualSelection(line: String) = selectionLock.withLock {
        check(prefs.edit().putString("configured", line).putString("best", line)
            .putLong("attempt", System.currentTimeMillis()).commit())
        selected.value = Selection(line, line)
        manualRevision.update { it + 1 }
    }

    suspend fun monitor() {
        combine(ByeDpi.strategy, NetworkObserver.state, manualRevision) { strategy, network, revision ->
            Triple(strategy, network, revision)
        }.collectLatest { (configured, network, revision) ->
            if (configured == null || network.id == null) return@collectLatest
            while (true) {
                delay(ByeDpiDailySchedule.remaining(System.currentTimeMillis(), prefs.getLong("attempt", 0)))
                currentCoroutineContext().ensureActive()
                try {
                    check(prefs.edit().putLong("attempt", System.currentTimeMillis()).commit())
                    val best = withTimeoutOrNull(30 * 60_000L) {
                        val catalog = try {
                            ByeDpiCatalog.load(true, automatic = true)
                        } catch (error: CancellationException) {
                            throw error
                        } catch (_: Exception) {
                            ByeDpiCatalog.load(false)
                        }
                        val strategies = (catalog["strategies"] as List<*>).filterIsInstance<String>()
                        val current = selected.value?.takeIf { it.configured == configured }?.best ?: configured
                        ByeDpiOptimizer { line ->
                            delay(150)
                            val result = ByeDpi.measure(line, network.revision)
                            ByeDpiMeasurement(result["YouTube"] as Long?, result["Google"] as Long?)
                        }.select(strategies, current)
                    }
                    currentCoroutineContext().ensureActive()
                    selectionLock.withLock {
                        if (best != null && manualRevision.value == revision && ByeDpi.strategy.value == configured &&
                            NetworkObserver.state.value == network) {
                            check(prefs.edit().putString("configured", configured).putString("best", best).commit())
                            selected.value = Selection(configured, best)
                            GlobalState.log("ByeDPI daily selection applied: $best")
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    GlobalState.log("ByeDPI daily selection unavailable: ${error.message}")
                    delay(ByeDpiDailySchedule.INTERVAL)
                }
            }
        }
    }
}
