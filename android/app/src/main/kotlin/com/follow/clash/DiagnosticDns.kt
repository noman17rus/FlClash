package com.follow.clash

internal fun isDiagnosticDnsResponse(query: ByteArray, reply: ByteArray): Boolean {
    if (!(query.size >= 12 && reply.size >= query.size &&
        reply[0] == query[0] && reply[1] == query[1] &&
        reply[2].toInt() and 0x80 != 0 && reply[2].toInt() and 0x02 == 0 &&
        reply[3].toInt() and 0x0f == 0 &&
        reply[4] == query[4] && reply[5] == query[5] &&
        query.copyOfRange(12, query.size).contentEquals(reply.copyOfRange(12, query.size)))) return false
    fun word(offset: Int): Int = (reply[offset].toInt() and 0xff) * 256 + (reply[offset + 1].toInt() and 0xff)
    var offset = query.size
    repeat(word(6)) {
        while (offset < reply.size) {
            val length = reply[offset++].toInt() and 0xff
            if (length == 0) break
            if (length and 0xc0 == 0xc0) {
                if (offset >= reply.size || ((length and 0x3f) * 256 + (reply[offset++].toInt() and 0xff)) >= reply.size) return false
                break
            }
            if (length > 63 || offset + length >= reply.size) return false
            offset += length
        }
        if (offset + 10 > reply.size) return false
        val type = word(offset)
        val family = word(offset + 2)
        val length = word(offset + 8)
        offset += 10
        if (offset + length > reply.size) return false
        if (type == 1 && family == 1 && length == 4) return true
        offset += length
    }
    return false
}
