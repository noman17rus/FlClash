package com.follow.clash

import android.content.Context
import com.follow.clash.common.GlobalState
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal object ByeDpiCatalog {
    private const val SOURCE = "https://raw.githubusercontent.com/romanvht/ByeByeDPI/master/app/src/main/assets/proxytest_strategies.list"
    private val prefs by lazy { GlobalState.application.getSharedPreferences("byedpi_catalog", Context.MODE_PRIVATE) }
    private val lock = Mutex()
    private val bundled by lazy {
        GlobalState.application.assets.open("byedpi/proxytest_strategies.list").bufferedReader().use { it.readText() }
    }

    suspend fun load(refresh: Boolean, automatic: Boolean = false): Map<String, Any> = withContext(Dispatchers.IO) {
        lock.withLock {
            val now = System.currentTimeMillis()
            if (refresh && (!automatic || now - prefs.getLong("attempt", 0) !in 0 until 86_400_000L)) {
                prefs.edit().putLong("attempt", now).apply()
                val connection = URL(SOURCE).openConnection() as HttpsURLConnection
                try {
                    connection.connectTimeout = 5000
                    connection.readTimeout = 7000
                    connection.instanceFollowRedirects = false
                    check(connection.responseCode == 200)
                    val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                        buildString {
                            val buffer = CharArray(4096)
                            while (true) {
                                val count = reader.read(buffer)
                                if (count < 0) break
                                require(length + count <= 512 * 1024)
                                append(buffer, 0, count)
                            }
                        }
                    }
                    ByeDpiStrategy.catalog(text)
                    check(prefs.edit().putString("list", text).putLong("updated", now).commit())
                } finally {
                    connection.disconnect()
                }
            }
            mapOf("strategies" to ByeDpiStrategy.catalog(prefs.getString("list", null) ?: bundled),
                "updated" to prefs.getLong("updated", 0))
        }
    }
}
