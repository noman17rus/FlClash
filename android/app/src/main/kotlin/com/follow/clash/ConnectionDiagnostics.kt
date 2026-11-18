package com.follow.clash

import android.net.Uri
import android.provider.Settings
import android.util.Base64
import com.follow.clash.common.GlobalState
import com.google.gson.Gson
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.net.Socket
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

internal object ConnectionDiagnostics {
    private val lock = Mutex()
    @Volatile private var results = emptyMap<String, String>()
    private val stages = listOf("vless", "turn", "dtls", "wireguard", "dns", "internet")

    fun snapshot(): Map<String, String> = results.toMap()

    private fun set(stage: String, status: String) {
        if (status == "running" && results[stage] == "passed") return
        results = results + (stage to status)
    }

    suspend fun run(profileId: Int?, link: String?): Map<String, String> {
        check(lock.tryLock()) { "Diagnostics already running" }
        try {
            results = stages.associateWith { "pending" }
            set("vless", "running")
            set("vless", if (profileId == null || ServiceController.runtime == null) "unavailable" else {
                if (probe {
                    val response = invokeFailoverMethod("proxy.testDelay", mapOf(
                        "proxy-name" to "VLESS [$profileId]",
                        "test-url" to "https://www.gstatic.com/generate_204",
                        "timeout" to 5_000,
                    ))
                    check(response.asJsonObject.get("value").asInt > 0)
                }) "passed" else "failed"
            })
            if (link.isNullOrBlank()) {
                stages.drop(1).forEach { set(it, "unavailable") }
            } else {
                withContext(Dispatchers.IO) { checkWdtt(link) }
            }
            return snapshot()
        } finally {
            stages.filter { results[it] in listOf("pending", "running") }.forEach { set(it, "blocked") }
            lock.unlock()
        }
    }

    private suspend fun probe(block: suspend () -> Unit): Boolean = try {
        block()
        true
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        false
    }

    private suspend fun checkWdtt(link: String) = coroutineScope {
        set("turn", "running")
        var client: Process? = null
        var reader: kotlinx.coroutines.Job? = null
        var stage = "turn"
        try {
            val uri = Uri.parse(link)
            val host = requireNotNull(uri.getQueryParameter("host"))
            val port = requireNotNull(uri.getQueryParameter("dtls")).toInt()
            require(host.isNotBlank() && port in 1..65535)
            val password = requireNotNull(uri.getQueryParameter("password"))
            val hashes = requireNotNull(uri.getQueryParameter("hashes"))
            require(password.isNotBlank() && hashes.isNotBlank())
            val context = GlobalState.application
            val localPort = ServerSocket(0).use { it.localPort }
            var socksPort = ServerSocket(0).use { it.localPort }
            while (socksPort == localPort) socksPort = ServerSocket(0).use { it.localPort }
            val peer = if (':' in host && !host.startsWith('[')) "[$host]" else host
            val process = ProcessBuilder(
                File(context.applicationInfo.nativeLibraryDir, "libclient.so").absolutePath,
                "-peer", "$peer:$port", "-startup-config-stdin=true", "-n", "9",
                "-listen", "127.0.0.1:$localPort", "-mode", "socks5",
                "-socks-listen", "127.0.0.1:$socksPort",
                "-device-id", Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID),
                "-captcha-mode", "auto",
            ).directory(context.cacheDir).redirectErrorStream(true).start()
            client = process
            val input = process.outputStream.bufferedWriter(Charsets.UTF_8)
            val config = Gson().toJson(mapOf("vk_hashes" to hashes, "connection_password" to password))
            input.write("START_CONFIG|" + Base64.encodeToString(config.toByteArray(Charsets.UTF_8),
                Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP) + "\n")
            input.flush()
            val ready = kotlinx.coroutines.CompletableDeferred<Boolean>()
            reader = launch(Dispatchers.IO) {
                try {
                    process.inputStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                        for (line in lines) {
                            if (ready.isCompleted) continue
                            when {
                                line.contains("Relay:") -> {
                                    set("turn", "passed")
                                    if (results["dtls"] != "passed") stage = "dtls"
                                    set("dtls", "running")
                                }
                                line.contains("[DTLS] Соединение установлено") -> {
                                    set("turn", "passed")
                                    set("dtls", "passed")
                                    stage = "wireguard"
                                    set("wireguard", "running")
                                }
                                line.contains("PROXY_READY|socks5|") -> {
                                    ready.complete(true)
                                }
                                line.startsWith("CAPTCHA_SOLVE|") -> {
                                    val request = line.split('|', limit = 5)
                                    if (request.size != 5 || request[2] != "auto") {
                                        set("turn", "captcha")
                                        ready.complete(false)
                                        break
                                    }
                                    val answer = WdttCaptcha.solveAutomatically(request[3])
                                    if (answer.startsWith("error:")) {
                                        set("turn", "captcha")
                                        ready.complete(false)
                                        break
                                    }
                                    input.write("CAPTCHA_RESULT|${request[1]}|$answer\n")
                                    input.flush()
                                }
                                line.contains("FATAL_AUTH") -> {
                                    set(stage, "auth")
                                    ready.complete(false)
                                    break
                                }
                                line.contains("PROXY_ERROR|") ||
                                    line.contains("FATAL_TRANSPORT") -> {
                                    ready.complete(false)
                                    break
                                }
                            }
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    ready.complete(false)
                } finally {
                    ready.complete(false)
                }
            }
            if (withTimeoutOrNull(100_000) { ready.await() } != true) {
                if (results[stage] !in listOf("captcha", "auth")) set(stage, "failed")
                return@coroutineScope
            }
            stage = "wireguard"
            set(stage, "running")
            if (!probe { socket(socksPort, "1.1.1.1", 443).close() }) {
                set(stage, "failed")
                return@coroutineScope
            }
            set(stage, "passed")
            set("dns", "running")
            set("dns", if (probe { checkDns(socksPort) }) "passed" else "failed")
            set("internet", "running")
            set("internet", if (probe { checkInternet(socksPort) }) "passed" else "failed")
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            set(stage, if (client == null) "unavailable" else "failed")
        } finally {
            withContext(NonCancellable + Dispatchers.IO) {
                client?.destroy()
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    if (client?.waitFor(2, java.util.concurrent.TimeUnit.SECONDS) == false) {
                        client.destroyForcibly()
                        check(client.waitFor(2, java.util.concurrent.TimeUnit.SECONDS))
                    }
                }
                client?.inputStream?.close()
                reader?.cancel()
                reader?.join()
                stages.drop(1).filter { results[it] in listOf("pending", "running") }
                    .forEach { set(it, "blocked") }
            }
        }
    }

    private fun socket(port: Int, host: String, targetPort: Int): Socket {
        val socket = Socket(Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", port)))
        try {
            socket.soTimeout = 8_000
            socket.connect(InetSocketAddress.createUnresolved(host, targetPort), 8_000)
            return socket
        } catch (error: Exception) {
            socket.close()
            throw error
        }
    }

    private fun checkDns(port: Int) {
        socket(port, "1.1.1.1", 53).use { socket ->
            val query = byteArrayOf(0x46, 0x43, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0) +
                byteArrayOf(7) + "example".toByteArray() + byteArrayOf(3) + "com".toByteArray() +
                byteArrayOf(0, 0, 1, 0, 1)
            DataOutputStream(socket.getOutputStream()).apply { writeShort(query.size); write(query); flush() }
            val input = DataInputStream(socket.getInputStream())
            val size = input.readUnsignedShort()
            check(size in 12..4096)
            val reply = ByteArray(size).also(input::readFully)
            check(isDiagnosticDnsResponse(query, reply))
        }
    }

    private fun checkInternet(port: Int) {
        val host = "www.gstatic.com"
        socket(port, host, 443).use { tcp ->
            val tls = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(tcp, host, 443, true) as SSLSocket
            tls.use {
                it.sslParameters = it.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
                it.soTimeout = 8_000
                it.startHandshake()
                it.outputStream.write("GET /generate_204 HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n".toByteArray())
                val line = it.inputStream.bufferedReader().readLine()
                check(line?.matches(Regex("HTTP/1\\.[01] 204(?: .*)?")) == true)
            }
        }
    }
}
