package com.follow.clash

internal enum class WdttProgress(val message: Int) {
    STARTING(R.string.wdtt_starting),
    CREDENTIALS(R.string.wdtt_credentials),
    RELAY(R.string.wdtt_relay),
    HANDSHAKE(R.string.wdtt_handshake),
    SECURE_CHANNEL(R.string.wdtt_secure_channel),
    CONFIGURATION(R.string.wdtt_configuration),
    CONNECTED(R.string.wdtt_connected);

    companion object {
        fun fromLog(line: String): WdttProgress? = when {
            line.contains("PROXY_READY|socks5|") -> CONNECTED
            line.contains("Конфиг получен") -> CONFIGURATION
            line.contains("[DTLS] Соединение установлено") -> SECURE_CHANNEL
            line.contains("Рукопожатие (Handshake)") -> HANDSHAKE
            line.contains("Relay:") -> RELAY
            line.contains("Запрос реквизитов подключения") -> CREDENTIALS
            else -> null
        }
    }
}
