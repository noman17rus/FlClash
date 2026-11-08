package com.follow.clash

import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import com.follow.clash.common.GlobalState
import com.google.gson.Gson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class WdttTunnel(private val onFailure: suspend (Process, String, Boolean) -> Unit) {
    @Volatile
    private var process: Process? = null

    @Volatile
    private var stopping = false

    fun owns(client: Process) = process === client

    suspend fun start(link: String, allowManualCaptcha: Boolean): Unit = withContext(Dispatchers.IO) {
        val uri = Uri.parse(link)
        val host = requireNotNull(uri.getQueryParameter("host")).trim()
        val peerHost = if (':' in host && !host.startsWith('[')) "[$host]" else host
        val dtlsPort = requireNotNull(uri.getQueryParameter("dtls")).toInt()
        val localPort = requireNotNull(uri.getQueryParameter("local")).toInt()
        val password = requireNotNull(uri.getQueryParameter("password"))
        val hashes = requireNotNull(uri.getQueryParameter("hashes"))
        val workers = uri.getQueryParameter("max_workers")?.toIntOrNull()
            ?.takeIf { it in 9..108 && it % 9 == 0 } ?: 9
        require(host.isNotEmpty() && dtlsPort in 1..65535 && localPort in 1..65535)
        require(password.isNotBlank() && hashes.isNotBlank())

        val context = GlobalState.application
        val deviceId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: error("Android device ID is unavailable")
        val binary = File(context.applicationInfo.nativeLibraryDir, "libclient.so")
        val client = ProcessBuilder(
            binary.absolutePath,
            "-peer", "$peerHost:$dtlsPort",
            "-startup-config-stdin=true",
            "-n", workers.toString(),
            "-listen", "127.0.0.1:$localPort",
            "-mode", "socks5",
            "-socks-listen", "127.0.0.1:1080",
            "-device-id", deviceId,
            "-captcha-mode", "auto",
        ).directory(context.cacheDir).redirectErrorStream(true).start()
        process = client
        stopping = false

        var progress = WdttProgress.STARTING
        fun reportProgress(next: WdttProgress) {
            if (!owns(client) || stopping || next.ordinal <= progress.ordinal) return
            progress = next
            val message = context.getString(next.message)
            GlobalState.log(message)
            context.showToast(message)
        }
        context.showToast(context.getString(R.string.wdtt_starting))

        val input = client.outputStream.bufferedWriter(Charsets.UTF_8)
        try {
            val config = Gson().toJson(
                mapOf("vk_hashes" to hashes, "connection_password" to password),
            )
            val encoded = Base64.encodeToString(
                config.toByteArray(Charsets.UTF_8),
                Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
            )
            input.write("START_CONFIG|$encoded\n")
            input.flush()
        } catch (error: Exception) {
            stop()
            throw error
        }

        val ready = CompletableDeferred<Boolean>()
        val manualCaptcha = AtomicBoolean(false)
        GlobalState.launch {
            if (withTimeoutOrNull(120_000) { ready.await() } == null) {
                if (manualCaptcha.get() && withTimeoutOrNull(180_000) { ready.await() } != null) {
                    return@launch
                }
                onFailure(client, "WDTT connection timed out", true)
            }
        }
        GlobalState.launch(Dispatchers.IO) {
            val captchaNotices = mutableSetOf<Int>()
            var lastFailure: String? = null
            var phase = "launch"
            var portInUse = false
            var authorizationRejected = false
            runCatching {
                client.inputStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                    lines.forEach { line ->
                        if (!owns(client) || stopping) return@forEach
                        WdttProgress.fromLog(line)?.let(::reportProgress)
                        phase = when {
                            line.contains("Конфиг получен") -> "WireGuard configuration"
                            line.contains("[DTLS] Соединение установлено") -> "DTLS established"
                            line.contains("Рукопожатие (Handshake)") -> "DTLS handshake"
                            line.contains("Relay:") -> "TURN relay"
                            line.contains("Запрос реквизитов подключения") -> "VK credentials"
                            else -> phase
                        }
                        if (line.startsWith("CAPTCHA_SOLVE|")) {
                            val request = line.split('|', limit = 5)
                            if (request.size != 5) return@forEach
                            val captchaMessage = if (request[2] == "auto") {
                                R.string.wdtt_captcha_auto
                            } else {
                                R.string.wdtt_captcha_manual
                            }
                            if (progress != WdttProgress.CONNECTED &&
                                (request[2] == "auto" || allowManualCaptcha) &&
                                captchaNotices.add(captchaMessage)
                            ) {
                                context.showToast(context.getString(captchaMessage))
                            }
                            val result = if (request[2] == "auto") {
                                try {
                                    WdttCaptcha.solveAutomatically(request[3]).also {
                                        if (!it.startsWith("error:")) GlobalState.log("WDTT solved VK CAPTCHA automatically")
                                    }
                                } catch (error: CancellationException) {
                                    throw error
                                } catch (_: Exception) {
                                    "error:automatic WebView failed"
                                }
                            } else if (allowManualCaptcha) {
                                manualCaptcha.set(true)
                                WdttCaptcha.solve(request[3])
                            } else {
                                "error:manual CAPTCHA required"
                            }
                            input.write("CAPTCHA_RESULT|${request[1]}|$result\n")
                            input.flush()
                        } else if (line.contains("PROXY_READY|socks5|")) {
                            ready.complete(true)
                            GlobalState.log("WDTT SOCKS5 is ready")
                        } else if (line.contains("PROXY_ERROR|port_in_use|")) {
                            portInUse = true
                        } else if (line.contains("FATAL_AUTH")) {
                            authorizationRejected = true
                            onFailure(client, "WDTT server rejected this device or password", false)
                        } else {
                            wdttFailureReason(line)?.let { reason ->
                                if (lastFailure != reason) GlobalState.log(reason)
                                lastFailure = reason
                            }
                        }
                    }
                }
            }.onFailure { error ->
                GlobalState.log("WDTT client output ended: ${error.javaClass.simpleName}")
            }
            val started = !ready.complete(false)
            val exitCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                client.waitFor(1, TimeUnit.SECONDS)
            ) client.exitValue() else runCatching { client.exitValue() }.getOrNull()
            val message = when {
                portInUse -> "WDTT: local SOCKS5 port 1080 is in use"
                authorizationRejected -> "WDTT server rejected this device or password"
                started -> "WDTT tunnel stopped"
                lastFailure != null -> "WDTT could not connect. $lastFailure"
                else -> "WDTT tunnel could not start ($phase, exit ${exitCode ?: "unknown"})"
            }
            if (owns(client)) onFailure(client, message, !portInUse && !authorizationRejected)
        }
    }

    private fun wdttFailureReason(line: String): String? = when {
        line.contains("CAPTCHA_WAIT_REQUIRED") -> "VK still requires CAPTCHA."
        line.contains("PROXY_ERROR|Не удалось запустить userspace WireGuard:") -> {
            val reason = when {
                line.contains("создание userspace TUN") -> "could not create the network interface"
                line.contains("применение WireGuard-конфигурации") -> "could not apply the configuration"
                line.contains("запуск WireGuard") -> "could not start the network interface"
                line.contains("DNS ") -> "invalid DNS server"
                line.contains("PrivateKey:") || line.contains("PublicKey:") -> "invalid key"
                line.contains("Endpoint") -> "missing or invalid endpoint"
                line.contains("строка ") -> "invalid configuration line"
                else -> "invalid configuration"
            }
            "WDTT WireGuard setup failed ($reason)."
        }
        line.contains("PROXY_ERROR|startup|") -> "WDTT could not start its local SOCKS5 listener."
        line.startsWith("panic:") || line.startsWith("fatal error:") -> "The WDTT native client crashed."
        line.contains("terminal join error") -> "VK declined the call invitation."
        line.contains("хеш мёртв", ignoreCase = true) -> "VK call invitation is unavailable."
        line.contains("чтение ответа конфига") -> "The WDTT server did not return its configuration."
        line.contains("проверка рабочего пути") -> "The WDTT server did not confirm the relay path."
        line.contains("согласование транспорта") || line.contains("FATAL_TRANSPORT") ->
            "The WDTT server did not negotiate transport."
        line.contains("Стартовые креды не получены") -> {
            val code = vkErrorCode.find(line)?.groupValues?.get(1)
            if (code != null) "VK did not issue TURN credentials (error $code)."
            else "VK did not issue initial TURN credentials."
        }
        else -> null
    }

    suspend fun stop() = withContext(Dispatchers.IO) {
        val client = process ?: return@withContext
        stopping = true
        WdttCaptcha.cancel()
        client.destroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!client.waitFor(2, TimeUnit.SECONDS)) {
                client.destroyForcibly()
                check(client.waitFor(2, TimeUnit.SECONDS)) { "WDTT client did not stop" }
            }
        } else {
            client.waitFor()
        }
        process = null
    }

    private companion object {
        val vkErrorCode = Regex("error_code:([0-9]{1,5})\\b")
    }
}
