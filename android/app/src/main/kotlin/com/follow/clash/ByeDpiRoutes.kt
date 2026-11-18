package com.follow.clash

import com.google.gson.JsonObject

internal object ByeDpiRoutes {
    suspend fun snapshot(): Map<String, Any?> {
        val proxies = invokeFailoverMethod("proxy.list", emptyMap()).asJsonObject.getAsJsonObject("proxies")
        val group = proxies.keySet().singleOrNull { it.startsWith("YouTube [") }
            ?: return mapOf("next" to "inactive", "connections" to emptyList<Any>())
        val suffix = group.removePrefix("YouTube ")
        val entries = invokeFailoverMethod("connection.list", emptyMap()).asJsonObject.getAsJsonArray("connections")
        return describe(proxies, entries?.map { it.asJsonObject }.orEmpty(), group, suffix)
    }

    internal fun describe(proxies: JsonObject, entries: List<JsonObject>, group: String, suffix: String): Map<String, Any?> {
        val selected = mutableListOf<String>()
        var name: String? = group
        while (name != null && name !in selected) {
            selected += name
            name = proxies.getAsJsonObject(name)?.get("now")?.takeUnless { it.isJsonNull }?.asString
        }
        val connections = entries.mapNotNull { entry ->
            val host = entry.getAsJsonObject("metadata")?.get("host")?.asString.orEmpty().lowercase().trimEnd('.')
            val chains = entry.getAsJsonArray("chains")?.map { it.asString }.orEmpty()
            val video = host == "googlevideo.com" || host.endsWith(".googlevideo.com")
            val youtube = listOf("youtube.com", "youtu.be", "ytimg.com", "youtube-nocookie.com",
                "youtubei.googleapis.com", "youtube.googleapis.com").any { host == it || host.endsWith(".$it") }
            if (group !in chains && !video && !youtube) return@mapNotNull null
            mapOf("host" to host, "route" to route(chains, suffix), "video" to video,
                "download" to (entry.get("download")?.asLong ?: 0))
        }.sortedByDescending { it["video"] == true }.take(20)
        return mapOf("next" to route(selected, suffix), "connections" to connections)
    }

    private fun route(chain: List<String>, suffix: String): String = when {
        "ByeDPI $suffix" in chain -> "ByeDPI"
        "WDTT $suffix" in chain -> "WDTT"
        "VLESS $suffix" in chain -> "VLESS"
        "DIRECT" in chain -> "DIRECT"
        else -> "unknown"
    }
}
