package com.follow.clash.plugins

import com.follow.clash.ServiceController
import com.follow.clash.ByeDpi
import com.follow.clash.ByeDpiCatalog
import com.follow.clash.ByeDpiRoutes
import com.follow.clash.ConnectionMode
import com.follow.clash.ConnectionDiagnostics
import com.follow.clash.ServiceState
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import com.follow.clash.models.SharedState
import com.follow.clash.service.NetworkObserver
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var messenger: BinaryMessenger
    private lateinit var channel: MethodChannel
    private lateinit var coreChannel: MethodChannel
    private lateinit var scope: CoroutineScope
    private val gson = Gson()
    private var commandRevision = 0
    private var byeDpiProbe: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        scope.launch {
            ByeDpi.strategy.collectLatest { strategy ->
                if (strategy != null) while (true) {
                    try { ByeDpiCatalog.load(true, automatic = true) }
                    catch (error: CancellationException) { throw error }
                    catch (_: Exception) { GlobalState.log("ByeDPI catalog update unavailable") }
                    delay(86_400_000)
                }
            }
        }
        // The main thread is also Flutter's UI thread, where "init" would load it.
        scope.launch {
            runCatching { Core.load() }
                .onFailure { error -> GlobalState.log("Unable to load the Core: $error") }
        }
        messenger = binding.binaryMessenger
        channel = MethodChannel(messenger, SERVICE_CHANNEL)
        channel.setMethodCallHandler(this)
        // Serial: watchRoute keeps the latest intent by the order calls reach the Core.
        coreChannel = MethodChannel(
            messenger,
            CORE_CHANNEL,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        )
        coreChannel.setMethodCallHandler(::onCoreMethodCall)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        coreChannel.setMethodCallHandler(null)
        scope.cancel()
        ServiceController.setEventListener(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> initialize(result)
            "shutdown" -> shutdown(result)
            "getRunTime" -> getRunTime(result)
            "getFailoverStatus", "byeDpiRoutes" -> scope.launch {
                try {
                    val routes = if (ByeDpi.strategy.value != null) ByeDpiRoutes.snapshot() else null
                    result.success(if (call.method == "byeDpiRoutes") routes
                        else ServiceController.failoverStatus()?.plus("youtube" to routes))
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    result.success(if (call.method == "byeDpiRoutes") null else ServiceController.failoverStatus())
                }
            }
            "byeDpiNetwork" -> result.success(NetworkObserver.state.value.revision)
            "byeDpiCatalog", "byeDpiValidate", "byeDpiProbe" -> {
                val job = scope.launch(Dispatchers.IO) {
                    try {
                        val value: Any = when (call.method) {
                            "byeDpiCatalog" -> ByeDpiCatalog.load(call.argument<Boolean>("refresh") == true,
                                call.argument<Boolean>("automatic") == true)
                            "byeDpiValidate" -> ByeDpi.validate(requireNotNull(call.argument<String>("strategy")))
                            else -> ByeDpi.measure(requireNotNull(call.argument<String>("strategy")),
                                requireNotNull(call.argument<Number>("revision")).toLong())
                        }
                        result.success(value)
                    } catch (error: CancellationException) {
                        result.error("CANCELLED", null, null)
                        throw error
                    } catch (error: Exception) {
                        result.error(if (error.message == "NETWORK_CHANGED") "NETWORK_CHANGED" else "BYEDPI",
                            error.localizedMessage ?: error.javaClass.simpleName, null)
                    }
                }
                if (call.method == "byeDpiProbe") { byeDpiProbe?.cancel(); byeDpiProbe = job }
            }
            "byeDpiCancel" -> { byeDpiProbe?.cancel(); result.success(null) }
            "getConnectionMode" -> result.success(ServiceController.connectionMode.name)
            "setConnectionMode" -> {
                val mode = ConnectionMode.entries.firstOrNull { it.name == call.arguments as? String }
                if (mode == null) {
                    result.error("INVALID_ARGUMENT", "Unknown connection mode", null)
                    return
                }
                scope.launch {
                    try {
                        ServiceController.setConnectionMode(mode)
                        withContext(Dispatchers.Main) { result.success(mode.name) }
                    } catch (error: kotlinx.coroutines.CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        withContext(Dispatchers.Main) { result.error("MODE_FAILED", "Unable to save connection mode", null) }
                    }
                }
            }
            "getDiagnostics" -> result.success(ConnectionDiagnostics.snapshot())
            "runDiagnostics" -> scope.launch {
                try {
                    val report = ConnectionDiagnostics.run(call.argument<Int>("profileId"), call.argument<String>("link"))
                    withContext(Dispatchers.Main) { result.success(report) }
                } catch (error: kotlinx.coroutines.CancellationException) {
                    throw error
                } catch (_: Exception) {
                    withContext(Dispatchers.Main) { result.error("DIAGNOSTICS_FAILED", "Diagnostics unavailable", null) }
                }
            }
            "syncState" -> syncState(call, result)
            "start" -> start(call, result)
            "stop" -> stop(call, result)
            else -> result.notImplemented()
        }
    }

    private fun onCoreMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "invokeMethod" -> invokeMethod(call, result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        NetworkObserver.start()
        ServiceController.setEventListener(::sendEvent)
            .onSuccess { result.success("") }
            .onFailure { error -> result.success(error.message.orEmpty()) }
    }

    private fun shutdown(result: MethodChannel.Result) {
        ServiceController.setEventListener(null)
        result.success(true)
    }

    private fun invokeMethod(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments as? String
        if (data == null) {
            result.error("INVALID_ARGUMENT", "Method call payload must be a string", null)
            return
        }
        ServiceController.invokeMethod(data) { response ->
            result.success(response)
        }.onFailure { error ->
            result.error("CORE_ERROR", error.message, null)
        }
    }

    private fun getRunTime(result: MethodChannel.Result) {
        scope.launch {
            result.success(ServiceState.awaitRunTime())
        }
    }

    private fun syncState(call: MethodCall, result: MethodChannel.Result) {
        val data = call.arguments as? String
        val state = runCatching {
            gson.fromJson(data, SharedState::class.java)
        }.getOrNull()
        if (state == null) {
            result.success("Invalid shared state")
            return
        }
        ServiceState.syncSharedState(state)
        result.success("")
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        commandRevision = call.arguments as? Int ?: commandRevision
        ServiceState.requestStart()
        result.success(true)
    }

    private fun stop(call: MethodCall, result: MethodChannel.Result) {
        commandRevision = call.arguments as? Int ?: commandRevision
        ServiceState.requestStop()
        result.success(true)
    }

    // Read on the platform thread, where start and stop arrive: revision and intent are one instant.
    fun notifyStopped() {
        scope.launch(Dispatchers.Main) {
            if (!ServiceState.isRunRequested) {
                channel.invokeMethod("stopped", commandRevision)
            }
        }
    }

    private fun sendEvent(value: ByteArray) {
        val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall("event", value))
        scope.launch(Dispatchers.Main) {
            messenger.send(SERVICE_CHANNEL, message)
        }
    }

    private companion object {
        val SERVICE_CHANNEL = "${Components.PACKAGE_NAME}/service"
        val CORE_CHANNEL = "${Components.PACKAGE_NAME}/core"
    }
}
