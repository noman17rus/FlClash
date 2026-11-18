package com.follow.clash

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticDnsTest {
    private val query = byteArrayOf(0x46, 0x43, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
        1, 97, 0, 0, 1, 0, 1)
    private val reply = query.clone().apply { this[2] = 0x81.toByte(); this[3] = 0x80.toByte(); this[7] = 1 } +
        byteArrayOf(0xc0.toByte(), 12, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 1, 1, 1, 1)

    @Test
    fun `DNS success requires a matching complete answer`() {
        assertTrue(isDiagnosticDnsResponse(query, reply))
        assertFalse(isDiagnosticDnsResponse(query, reply.copyOf(8)))
        assertFalse(isDiagnosticDnsResponse(query, reply.copyOf(reply.size - 1)))
        assertFalse(isDiagnosticDnsResponse(query, reply.copyOf(query.size)))
        assertFalse(isDiagnosticDnsResponse(query, reply.clone().apply { this[0] = 0 }))
        assertFalse(isDiagnosticDnsResponse(query, reply.clone().apply { this[7] = 0 }))
        assertFalse(isDiagnosticDnsResponse(query, reply.clone().apply { this[3] = 3 }))
        assertFalse(isDiagnosticDnsResponse(query, reply.clone().apply { this[2] = 0x83.toByte() }))
        assertFalse(isDiagnosticDnsResponse(query, query))
    }
}
