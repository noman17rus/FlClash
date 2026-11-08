package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WdttProgressTest {
    @Test
    fun `native log stages distinguish secure channel from ready tunnel`() {
        assertEquals(WdttProgress.CREDENTIALS, WdttProgress.fromLog("[ГРУППА #0] Запрос реквизитов подключения"))
        assertEquals(WdttProgress.RELAY, WdttProgress.fromLog("[СЕССИЯ #0] Relay: 127.0.0.1"))
        assertEquals(WdttProgress.HANDSHAKE, WdttProgress.fromLog("[ВОРКЕР #0] [DTLS] Рукопожатие (Handshake)..."))
        assertEquals(WdttProgress.SECURE_CHANNEL, WdttProgress.fromLog("[ВОРКЕР #0] [DTLS] Соединение установлено ✓"))
        assertEquals(WdttProgress.CONFIGURATION, WdttProgress.fromLog("[ВОРКЕР #0] Конфиг получен"))
        assertEquals(WdttProgress.CONNECTED, WdttProgress.fromLog("PROXY_READY|socks5|127.0.0.1:1080|udp=true|auth=false"))
    }

    @Test
    fun `errors and other proxy modes never announce a ready tunnel`() {
        assertNull(WdttProgress.fromLog("PROXY_ERROR|startup|failure"))
        assertNull(WdttProgress.fromLog("PROXY_READY|http|127.0.0.1:8080"))
        assertNull(WdttProgress.fromLog("CAPTCHA_SOLVE|1|auto|url|data"))
    }
}
