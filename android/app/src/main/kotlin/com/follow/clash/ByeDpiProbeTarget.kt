package com.follow.clash

internal enum class ByeDpiProbeTarget(val host: String, val path: String, private val status: String) {
    GOOGLE("www.gstatic.com", "/generate_204", "204"),
    YOUTUBE("www.youtube.com", "/", "200");

    fun accepts(statusLine: String?): Boolean {
        val parts = statusLine?.split(' ') ?: return false
        return parts.size >= 2 && parts[0] in listOf("HTTP/1.0", "HTTP/1.1") && parts[1] == status
    }
}
