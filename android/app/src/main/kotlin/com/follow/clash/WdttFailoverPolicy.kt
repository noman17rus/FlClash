package com.follow.clash

internal class WdttFailoverPolicy {
    var backup = false
        private set
    private var failures = 0
    private var successes = 0
    private var failedSince = 0L
    private var stableAt = 0L

    fun networkChanged(now: Long) {
        failures = 0
        successes = 0
        stableAt = now + 4_000
    }

    fun canProbe(now: Long) = now >= stableAt

    fun sample(healthy: Boolean, now: Long): Boolean {
        if (!canProbe(now)) return backup
        if (healthy) {
            failures = 0
            if (++successes >= 2) backup = false
        } else {
            successes = 0
            if (failures++ == 0) failedSince = now
            if (failures >= 2 && now - failedSince >= 8_000) backup = true
        }
        return backup
    }
}
