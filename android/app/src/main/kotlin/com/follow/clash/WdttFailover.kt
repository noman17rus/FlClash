package com.follow.clash

import android.os.SystemClock
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import com.follow.clash.service.NetworkObserver
import com.follow.clash.service.UnderlyingNetworkState
import com.google.gson.JsonElement
import com.google.gson.JsonParser
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume

internal class WdttFailover(
    private val reconcile: suspend (needed: Boolean, networkChanged: Boolean) -> Boolean,
    private val networkState: () -> UnderlyingNetworkState = { NetworkObserver.state.value },
    private val clock: () -> Long = { SystemClock.elapsedRealtime() },
    private val rpc: suspend (String, Map<String, Any>) -> JsonElement = ::invokeFailoverMethod,
) {
    private val policy = WdttFailoverPolicy()
    private var revision = -1L
    private var nextProbe = 0L
    private var routeMode: String? = null
    private var restart = false
    private var offlineSince: Long? = null

    suspend fun run() = coroutineScope {
        while (isActive) {
            try {
                tick()
            } catch (_: TimeoutCancellationException) {
                GlobalState.log("Tunnel failover check did not receive a Core response")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                GlobalState.log("Tunnel failover check failed: ${error.javaClass.simpleName}")
            }
            delay(2_000)
        }
    }

    internal suspend fun tick() {
        val network = networkState()
        val now = clock()
        if (revision != network.revision) {
            restart = revision >= 0
            revision = network.revision
            policy.networkChanged(now)
            nextProbe = 0
        }
        if (network.id == null) {
            val since = offlineSince ?: now.also { offlineSince = it }
            if (now - since >= 15_000) reconcile(false, false)
            return
        }
        offlineSince = null
        if (!policy.canProbe(now)) return
        val proxies = call("proxy.list").asJsonObject.getAsJsonObject("proxies")
        val route = proxies.keySet().singleOrNull { it.startsWith("VLESS / WDTT [") } ?: return
        val suffix = route.removePrefix("VLESS / WDTT ")
        val primary = "VLESS $suffix"
        val backup = "WDTT $suffix"
        val automatic = "Auto $suffix"
        val mode = proxies.getAsJsonObject(route).get("now").asString
        if (routeMode != mode) {
            if (routeMode != null) policy.networkChanged(now)
            routeMode = mode
            nextProbe = 0
        }
        if (mode == primary) {
            reconcile(false, false)
            return
        }
        var needed = mode == backup
        if (mode == automatic) {
            if (now >= nextProbe && policy.canProbe(now)) {
                val primaryGroup = proxies.getAsJsonObject(primary)
                val members = primaryGroup.getAsJsonArray("all").map { it.asString }
                val testUrl = primaryGroup.get("testUrl").asString
                val healthy = probe(members, testUrl) { networkState() == network }
                val latest = networkState()
                if (latest != network) return
                val current = call("proxy.list").asJsonObject.getAsJsonObject("proxies")
                if (networkState() != network || current.getAsJsonObject(route)?.get("now")?.asString != mode) return
                policy.sample(healthy, clock())
                nextProbe = clock() + when {
                    policy.backup && !healthy -> 30_000
                    !policy.backup && healthy -> 15_000
                    else -> 5_000
                }
            }
            needed = policy.backup
        }
        if (mode != automatic && mode != backup) return
        if (networkState() != network) return
        val selected = proxies.getAsJsonObject(automatic).get("now").asString
        if (!needed && mode == automatic && selected != primary) select(automatic, primary)
        val ready = reconcile(needed, restart)
        restart = false
        if (mode == automatic && needed && ready && selected != backup) select(automatic, backup)
    }

    private suspend fun probe(members: List<String>, testUrl: String, current: () -> Boolean): Boolean {
        for (chunk in members.chunked(4)) {
            val results = coroutineScope {
                chunk.map { name ->
                    async {
                        val result = call("proxy.testDelay", mapOf(
                            "proxy-name" to name,
                            "test-url" to testUrl,
                            "timeout" to 5_000,
                        ))
                        result.takeUnless { it.isJsonNull }?.asJsonObject?.get("value")?.asInt?.let { it > 0 }
                    }
                }.awaitAll()
            }
            if (!current()) return false
            if (results.any { it == true }) return true
            check(results.none { it == null }) { "Core did not measure a primary proxy" }
        }
        return false
    }

    private suspend fun select(group: String, proxy: String) {
        val result = call("proxy.select", mapOf("group-name" to group, "proxy-name" to proxy)).asJsonObject
        check(result.get("message")?.asString.orEmpty().isEmpty()) { "Core refused tunnel selection" }
        if (result.get("changed")?.asBoolean == true) call("connection.closeAll")
    }

    private suspend fun call(method: String, arguments: Map<String, Any> = emptyMap()): JsonElement =
        rpc(method, arguments)
}

private suspend fun invokeFailoverMethod(method: String, arguments: Map<String, Any>): JsonElement {
    val request = com.google.gson.Gson().toJson(mapOf("method" to method, "arguments" to arguments))
    val bytes = withTimeout(15_000) {
        suspendCancellableCoroutine<ByteArray> { continuation ->
            Core.invokeMethod(request) { result ->
                if (continuation.isActive) continuation.resume(result ?: ByteArray(0))
            }
        }
    }
    var response = JsonParser.parseString(bytes.decodeToString()).asJsonObject
    response.get("file")?.asString?.takeIf { it.isNotEmpty() }?.let { path ->
        val file = File(path).canonicalFile
        val root = File(GlobalState.application.applicationInfo.dataDir).canonicalFile
        check(file.parentFile?.name == "responses" && file.toPath().startsWith(root.toPath()))
        response = JsonParser.parseString(file.readText()).asJsonObject
        file.delete()
    }
    check(!response.has("error")) { "Core refused $method" }
    return response.get("result") ?: error("Core did not answer $method")
}
