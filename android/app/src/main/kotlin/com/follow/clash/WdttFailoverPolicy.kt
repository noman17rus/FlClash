package com.follow.clash

internal class WdttFailoverPolicy(var mode: ConnectionMode = ConnectionMode.balanced) {
    var backup = false
        private set
    private var failures = 0
    private var successes = 0
    private var failedSince = 0L
    private var recoveredSince = 0L
    private var stableAt = 0L

    val recovering: Boolean get() = backup && successes > 0

    fun networkChanged(now: Long) {
        failures = 0
        successes = 0
        stableAt = now + 4_000
    }

    fun canProbe(now: Long) = now >= stableAt

    fun sample(healthy: Boolean?, now: Long): Boolean {
        if (!canProbe(now)) return backup
        if (healthy == true) {
            failures = 0
            if (successes++ == 0) recoveredSince = now
            if (successes >= 3 && now - recoveredSince >= mode.recoveryWindow) backup = false
        } else {
            successes = 0
            if (healthy == null) return backup
            if (failures++ == 0) failedSince = now
            if (failures >= 2 && now - failedSince >= mode.failureWindow) backup = true
        }
        return backup
    }
}
