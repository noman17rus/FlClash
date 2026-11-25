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
    private val connectionMode: () -> ConnectionMode = { ConnectionMode.balanced },
) {
    val status = WdttFailoverStatus()
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
                status.update(phase = "error")
                GlobalState.log("Tunnel failover check did not receive a Core response")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                status.update(phase = "error")
                GlobalState.log("Tunnel failover check failed: ${error.javaClass.simpleName}")
            }
            delay(connectionMode().pollInterval)
        }
    }

    internal suspend fun tick() {
        val network = networkState()
        val now = clock()
        val modeSetting = connectionMode()
        if (policy.mode != modeSetting) {
            policy.mode = modeSetting
            policy.networkChanged(now)
            nextProbe = 0
        }
        if (revision != network.revision) {
            restart = revision >= 0
            revision = network.revision
            policy.networkChanged(now)
            nextProbe = 0
        }
        if (network.id == null) {
            status.update(phase = "offline")
            val since = offlineSince ?: now.also { offlineSince = it }
            if (now - since >= 15_000) reconcile(false, false)
            return
        }
        offlineSince = null
        if (!policy.canProbe(now)) {
            status.update(phase = "checking")
            return
        }
        val proxies = call("proxy.list").asJsonObject.getAsJsonObject("proxies")
        val route = proxies.keySet().singleOrNull { it.startsWith("VLESS / WDTT [") } ?: return
        val suffix = route.removePrefix("VLESS / WDTT ")
        val primary = "VLESS $suffix"
        val primaryTransport = "VLESS transport $suffix"
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
            if (now >= nextProbe && policy.canProbe(now)) {
                val group = proxies.getAsJsonObject(primaryTransport)
                try {
                    val healthy = probe(primaryTransport, group.getAsJsonArray("all").map { it.asString }, group.get("testUrl").asString) {
                        networkState() == network && connectionMode() == modeSetting
                    }
                    if (networkState() == network && connectionMode() == modeSetting) {
                        status.primaryMeasured(healthy, network.revision, route)
                    }
                } finally {
                    nextProbe = clock() + modeSetting.primaryInterval
                }
            }
            status.update(route, "manualVless", "VLESS")
            return
        }
        var needed = mode == backup
        if (mode == automatic) {
            if (now >= nextProbe && policy.canProbe(now)) {
                nextProbe = clock() + modeSetting.confirmationInterval
                val primaryGroup = proxies.getAsJsonObject(primaryTransport)
                val members = primaryGroup.getAsJsonArray("all").map { it.asString }
                val testUrl = primaryGroup.get("testUrl").asString
                val healthy = try {
                    probe(primaryTransport, members, testUrl) { networkState() == network }
                } catch (error: Exception) {
                    policy.sample(null, clock())
                    nextProbe = clock() + modeSetting.confirmationInterval
                    throw error
                }
                val latest = networkState()
                if (latest != network || connectionMode() != modeSetting) return
                val current = call("proxy.list").asJsonObject.getAsJsonObject("proxies")
                if (networkState() != network || current.getAsJsonObject(route)?.get("now")?.asString != mode) return
                status.primaryMeasured(healthy, network.revision, route)
                policy.sample(healthy, clock())
                nextProbe = clock() + when {
                    policy.backup && !healthy -> modeSetting.backupInterval
                    !policy.backup && healthy -> modeSetting.primaryInterval
                    else -> modeSetting.confirmationInterval
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
        status.update(
            route,
            when {
                needed && !ready -> if (mode == backup) "startingManual" else "starting"
                mode == backup -> "manualWdtt"
                policy.recovering -> "recovering"
                needed -> "backup"
                else -> "primary"
            },
            if (needed && ready) "WDTT" else if (!needed) "VLESS" else null,
        )
    }

    private suspend fun probe(primary: String, members: List<String>, testUrl: String, current: () -> Boolean): Boolean {
        val alternateUrls = listOf(
            "https://www.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
            "https://www.apple.com/library/test/success.html",
        ).filter { it != testUrl }
        // Alternate URLs must test the group's actual route, not an unselected member.
        val batches = members.map { it to testUrl }.chunked(4) +
            alternateUrls.map { primary to it }.chunked(4)
        var unmeasured = members.isEmpty()
        for (batch in batches) {
            if (!current()) return false
            val results = coroutineScope {
                batch.map { (name, url) ->
                    async {
                        val result = call("proxy.testDelay", mapOf(
                            "proxy-name" to name,
                            "test-url" to url,
                            "timeout" to 5_000,
                        ))
                        result.takeUnless { it.isJsonNull }?.asJsonObject?.get("value")?.asInt?.let { it > 0 }
                    }
                }.awaitAll()
            }
            if (!current()) return false
            if (results.any { it == true }) return true
            unmeasured = unmeasured || results.any { it == null }
        }
        check(!unmeasured) { "Core did not measure a primary proxy" }
        return false
    }

    private suspend fun select(group: String, proxy: String) {
        val result = call("proxy.select", mapOf("group-name" to group, "proxy-name" to proxy)).asJsonObject
        check(result.get("message")?.asString.orEmpty().isEmpty()) { "Core refused tunnel selection" }
    }

    private suspend fun call(method: String, arguments: Map<String, Any> = emptyMap()): JsonElement =
        rpc(method, arguments)
}

internal suspend fun invokeFailoverMethod(method: String, arguments: Map<String, Any>): JsonElement {
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
