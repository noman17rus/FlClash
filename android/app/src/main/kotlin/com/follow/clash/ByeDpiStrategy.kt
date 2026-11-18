package com.follow.clash

internal object ByeDpiStrategy {
    private val words = Regex("""(?:[^\s"']+|"[^"]*"|'[^']*')+""")
    private val aliases = mapOf(
        "split" to 's', "disorder" to 'd', "oob" to 'o', "disoob" to 'q', "fake" to 'f',
        "ttl" to 't', "tlsrec" to 'r', "tlsminor" to 'm', "udp-fake" to 'a', "fake-sni" to 'n',
        "fake-offset" to 'O', "fake-tls-mod" to 'Q', "mod-http" to 'M', "oob-data" to 'e',
        "auto" to 'A', "auto-mode" to 'L', "cache-ttl" to 'u', "timeout" to 'T', "proto" to 'K',
        "pf" to 'V', "round" to 'R', "def-ttl" to 'g', "md5sig" to 'S', "drop-sack" to 'Y',
        "wait-send" to 'Z', "await-int" to 'W', "hosts" to 'H', "ipset" to 'j',
    )

    fun arguments(strategy: String): List<String> {
        require(strategy.length in 1..4096 && strategy.none { it == '\u0000' || it == '\n' || it == '\r' })
        val line = strategy.trim().replace("{sni}", "google.com")
        val tokens = words.findAll(line).toList()
        var end = 0
        val values = tokens.map {
            require(line.substring(end, it.range.first).isBlank())
            end = it.range.last + 1
            it.value.replace("\"", "").replace("'", "")
        }
        require(line.substring(end).isBlank() && values.isNotEmpty())
        val args = mutableListOf<String>()
        var i = 0
        while (i < values.size) {
            val token = values[i++]
            require(token.startsWith('-') && token.length >= 2)
            val long = token.startsWith("--")
            val flag = if (long) aliases[token.drop(2).substringBefore('=')] else token[1]
            require(flag != null && flag in aliases.values) { "Unsupported ByeDPI option: ${token.take(32)}" }
            val inline = if (long) token.substringAfter('=', "") else token.drop(2)
            args.add("-$flag")
            if (flag in "SYZ") {
                require(inline.isEmpty())
            } else {
                val value = inline.ifEmpty { require(i < values.size); values[i++] }
                require(value.isNotBlank() && '{' !in value && '}' !in value)
                if (flag == 'H' || flag == 'j') require(value.startsWith(':'))
                args.add(value)
            }
        }
        return args
    }

    fun catalog(text: String): List<String> {
        require(text.length <= 512 * 1024)
        val entries = text.lineSequence().map(String::trim)
            .filter { it.isNotEmpty() && !it.startsWith('#') }.distinct().toList()
        require(entries.size in 1..1024)
        entries.forEach(::arguments)
        return entries
    }
}
