package com.follow.clash

import android.os.SystemClock
import com.follow.clash.common.GlobalState
import com.follow.clash.service.NetworkObserver
import java.io.DataInputStream
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import android.os.Build
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.withContext

internal object ByeDpi {
    private const val PORT = 11081
    val strategy = MutableStateFlow<String?>(null)
    private val loopback = InetAddress.getByName("127.0.0.1")

    private fun running(child: Process): Boolean = try {
        child.exitValue()
        false
    } catch (_: IllegalThreadStateException) {
        true
    }

    private suspend fun <T> withProxy(
        line: String, port: Int, network: Long?, use: suspend (Process) -> T,
    ): T = withContext(Dispatchers.IO) {
        val args = ByeDpiStrategy.arguments(line)
        val context = GlobalState.application
        val binary = File(context.applicationInfo.nativeLibraryDir, "libbyedpi.so")
        val builder = ProcessBuilder(listOf(binary.absolutePath, "-i", "127.0.0.1", "-p", port.toString()) + args)
            .directory(context.cacheDir).redirectErrorStream(true)
        network?.let { builder.environment()["FLCLASH_NETWORK"] = it.toString() }
        val child = builder.start()
        try {
            child.outputStream.close()
            thread(isDaemon = true, name = "ByeDPI output") {
                runCatching { child.inputStream.use { stream ->
                    val buffer = ByteArray(1024)
                    while (stream.read(buffer) >= 0) Unit
                } }
            }
            val deadline = SystemClock.elapsedRealtime() + 2500
            while (true) {
                check(running(child)) { "ByeDPI exited (${child.exitValue()})" }
                if (runCatching { Socket().use { greet(it, port) } }.isSuccess) break
                check(SystemClock.elapsedRealtime() < deadline) { "ByeDPI did not open its SOCKS5 port" }
                delay(35)
            }
            check(running(child))
            use(child)
        } finally {
            child.destroy()
            if (Build.VERSION.SDK_INT >= 26 && !child.waitFor(1, TimeUnit.SECONDS)) {
                child.destroyForcibly()
            }
            child.waitFor()
        }
    }

    private fun greet(socket: Socket, port: Int) {
        socket.connect(InetSocketAddress(loopback, port), 300)
        socket.soTimeout = 500
        socket.getOutputStream().write(byteArrayOf(5, 1, 0))
        val input = DataInputStream(socket.getInputStream())
        check(input.readUnsignedShort() == 0x0500)
    }

    suspend fun monitor(): Unit = coroutineScope {
        launch { ByeDpiAutoSelect.monitor() }
        var working: String? = null
        combine(ByeDpiAutoSelect.effectiveStrategy, NetworkObserver.state) { line, network -> line to network.id }.collectLatest { (line, network) ->
            if (line == null) { working = null; return@collectLatest }
            if (network == null) return@collectLatest
            var candidate: String = line
            while (true) {
                try {
                    withProxy(candidate, PORT, network) { child ->
                        working = candidate
                        while (running(child)) delay(1000)
                        error("ByeDPI stopped")
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    GlobalState.log("ByeDPI: ${error.message}")
                    val previous = working
                    if (previous != null && previous != candidate) {
                        GlobalState.application.showToast("ByeDPI: ${error.message}")
                        candidate = previous
                    } else delay(5000)
                }
            }
        }
    }

    private fun temporaryPort() = ServerSocket(0, 1, loopback).use { it.localPort }

    suspend fun validate(line: String) = withProxy(line, temporaryPort(), null) { true }

    suspend fun measure(line: String, revision: Long): Map<String, Any?> {
        val network = NetworkObserver.state.value
        check(network.revision == revision && network.id != null) { "NETWORK_CHANGED" }
        val port = temporaryPort()
        val times = withProxy(line, port, network.id) {
            coroutineScope {
                val google = async(Dispatchers.IO) { measureHost(port, ByeDpiProbeTarget.GOOGLE) }
                val youtube = async(Dispatchers.IO) {
                    val first = measureHost(port, ByeDpiProbeTarget.YOUTUBE)
                    if (first.delay != null) first else measureHost(port, ByeDpiProbeTarget.YOUTUBE)
                }
                val googleResult = google.await()
                val youtubeResult = youtube.await()
                mapOf("Google" to googleResult.delay, "YouTube" to youtubeResult.delay,
                    "YouTubeError" to youtubeResult.error)
            }
        }
        check(NetworkObserver.state.value == network) { "NETWORK_CHANGED" }
        return times
    }

    private data class Measurement(val delay: Long? = null, val error: String? = null)

    private fun measureHost(port: Int, target: ByeDpiProbeTarget): Measurement {
        var stage = "SOCKS5"
        return try {
            val host = target.host
            val start = SystemClock.elapsedRealtime()
            Socket().use { socket ->
                greet(socket, port)
                socket.soTimeout = 8000
                val name = host.toByteArray(Charsets.US_ASCII)
                socket.getOutputStream().write(byteArrayOf(5, 1, 0, 3, name.size.toByte()) + name + byteArrayOf(1, 0xbb.toByte()))
                val input = DataInputStream(socket.getInputStream())
                check(input.readUnsignedShort() == 0x0500 && input.readUnsignedByte() == 0)
                val size = when (input.readUnsignedByte()) {
                    1 -> 4
                    3 -> input.readUnsignedByte()
                    4 -> 16
                    else -> error("SOCKS5 address")
                }
                input.readFully(ByteArray(size + 2))
                val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
                stage = "TLS"
                (factory.createSocket(socket, host, 443, true) as SSLSocket).use { tls ->
                    tls.soTimeout = 8000
                    tls.sslParameters = tls.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
                    tls.startHandshake()
                    stage = "HTTP"
                    tls.outputStream.write("GET ${target.path} HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
                    val status = tls.inputStream.bufferedReader().readLine()
                    if (!target.accepts(status)) return Measurement(error = status?.take(80) ?: "HTTP · EOF")
                }
            }
            Measurement(delay = SystemClock.elapsedRealtime() - start)
        } catch (error: Exception) {
            Measurement(error = "$stage · ${error.javaClass.simpleName}")
        }
    }
}
