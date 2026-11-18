package com.follow.clash

internal enum class ConnectionMode(
    val primaryInterval: Long,
    val backupInterval: Long,
    val confirmationInterval: Long,
    val failureWindow: Long,
    val recoveryWindow: Long,
    val retryInterval: Long,
    val pollInterval: Long,
) {
    economical(60_000, 120_000, 15_000, 15_000, 60_000, 180_000, 5_000),
    balanced(15_000, 30_000, 5_000, 8_000, 30_000, 60_000, 2_000),
    fastRecovery(5_000, 10_000, 2_000, 4_000, 10_000, 15_000, 1_000);

    companion object {
        fun fromName(name: String?) = entries.firstOrNull { it.name == name } ?: balanced
    }
}
