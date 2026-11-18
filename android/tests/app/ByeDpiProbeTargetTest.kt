package com.follow.clash

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ByeDpiProbeTargetTest {
    @Test fun youtubeHomePageDoesNotRequire204() {
        assertTrue(ByeDpiProbeTarget.YOUTUBE.accepts("HTTP/1.1 200 OK"))
        assertFalse(ByeDpiProbeTarget.YOUTUBE.accepts("HTTP/1.1 403 Forbidden"))
        assertFalse(ByeDpiProbeTarget.YOUTUBE.accepts("HTTP/1.1 302 Found"))
        assertFalse(ByeDpiProbeTarget.YOUTUBE.accepts(null))
        assertFalse(ByeDpiProbeTarget.YOUTUBE.accepts("INVALID 200"))
        assertFalse(ByeDpiProbeTarget.GOOGLE.accepts("HTTP/1.1 200 OK"))
    }
}
