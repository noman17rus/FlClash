package com.follow.clash

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import kotlin.coroutines.resume

internal object WdttCaptcha {
    class Challenge(val url: String) {
        val result = CompletableDeferred<String>()
        var activity: Activity? = null
    }

    var current: Challenge? = null
        private set

    suspend fun solve(url: String): String = withContext(Dispatchers.Main) {
        if (!isVkUrl(Uri.parse(url))) return@withContext "error:invalid VK challenge URL"
        if (current != null) return@withContext "error:captcha already open"
        val challenge = Challenge(url)
        current = challenge
        try {
            val app = GlobalState.application
            app.startActivity(Intent(app, WdttCaptchaActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            withTimeoutOrNull(180_000) { challenge.result.await() } ?: "error:timeout"
        } finally {
            current = null
            challenge.activity?.finish()
        }
    }

    suspend fun cancel() = withContext(Dispatchers.Main) {
        current?.result?.complete("error:cancelled")
    }

    suspend fun solveAutomatically(url: String): String = withContext(Dispatchers.Main) {
        if (!isVkUrl(Uri.parse(url))) return@withContext "error:invalid VK challenge URL"
        if (current != null) return@withContext "error:captcha already open"
        val challenge = Challenge(url)
        val view = createWebView(GlobalState.application, challenge)
        current = challenge
        try {
            val metrics = view.resources.displayMetrics
            val width = View.MeasureSpec.makeMeasureSpec(metrics.widthPixels, View.MeasureSpec.EXACTLY)
            val height = View.MeasureSpec.makeMeasureSpec(metrics.heightPixels, View.MeasureSpec.EXACTLY)
            view.measure(width, height)
            view.layout(0, 0, view.measuredWidth, view.measuredHeight)
            view.loadUrl(url)
            withTimeoutOrNull(18_000) {
                while (!challenge.result.isCompleted) {
                    delay(400)
                    val position = view.evaluate(checkboxPosition)
                    if (position == "\"slider\"") return@withTimeoutOrNull "error:slider detected"
                    if (position?.startsWith('[') == true) {
                        val point = JSONArray(position)
                        view.tap(
                            point.getDouble(0).toFloat() * metrics.density,
                            point.getDouble(1).toFloat() * metrics.density,
                        )
                        break
                    }
                }
                challenge.result.await()
            } ?: "error:automatic WebView timed out"
        } finally {
            current = null
            view.destroy()
        }
    }

    private suspend fun WebView.evaluate(script: String): String? =
        suspendCancellableCoroutine { continuation ->
            evaluateJavascript(script) { continuation.resume(it) }
        }

    private suspend fun WebView.tap(x: Float, y: Float) {
        val now = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
            if (action == MotionEvent.ACTION_UP) delay(150)
            val event = MotionEvent.obtain(now, SystemClock.uptimeMillis(), action, x, y, 0)
            try {
                event.source = InputDevice.SOURCE_TOUCHSCREEN
                dispatchTouchEvent(event)
            } finally {
                event.recycle()
            }
        }
    }

    private val checkboxPosition = """
        (() => {
          if (document.querySelector('[class*="SliderCaptcha"], [class*="Kaleidoscope"], [class*="SwipeButton"]')) return 'slider';
          const label = document.querySelector('label.vkc__Checkbox-module__Checkbox, label[for="not-robot-captcha-checkbox"], #not-robot-captcha-checkbox');
          const target = label?.querySelector('[class*="iconBlock"], [class*="IconBlock"]') || label;
          const rect = target?.getBoundingClientRect();
          if (!rect || rect.width < 5 || rect.height < 5) return null;
          return [rect.left + Math.min(rect.width, rect.height) / 2, rect.top + rect.height / 2];
        })();
    """.trimIndent()

    fun isVkUrl(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: return false
        return uri.scheme == "https" && listOf("vk.com", "vk.ru", "vkontakte.ru").any {
            host == it || host.endsWith(".$it")
        }
    }
    fun createWebView(context: Context, request: Challenge): WebView =
        WebView(context).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowContentAccess = false
            settings.allowFileAccess = false
            addJavascriptInterface(object {
                @JavascriptInterface
                fun onSuccess(token: String) {
                    if (token.length in 1..4096 && token.none { it.isISOControl() }) {
                        request.result.complete(token)
                    }
                }
            }, "WdttCaptcha")
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    request.isForMainFrame && !isVkUrl(request.url)

                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    if (isVkUrl(Uri.parse(url))) view.evaluateJavascript(captureToken, null)
                }

                override fun onPageFinished(view: WebView, url: String) {
                    if (isVkUrl(Uri.parse(url))) view.evaluateJavascript(captureToken, null)
                }
            }
            webChromeClient = WebChromeClient()
        }

    private val captureToken = """
            (() => {
              if (window.wdttCaptchaHook) return;
              window.wdttCaptchaHook = true;
              const isCheck = url => String(url).includes('captchaNotRobot.check');
              const deliver = json => {
                const token = json?.response?.success_token;
                if (typeof token === 'string') window.WdttCaptcha.onSuccess(token);
              };
              const fetchOriginal = window.fetch;
              window.fetch = async function(input, options) {
                const response = await fetchOriginal.call(this, input, options);
                if (isCheck(typeof input === 'string' ? input : input?.url)) {
                  response.clone().json().then(deliver).catch(() => {});
                }
                return response;
              };
              const openOriginal = XMLHttpRequest.prototype.open;
              XMLHttpRequest.prototype.open = function(method, url, ...args) {
                const result = openOriginal.call(this, method, url, ...args);
                if (isCheck(url)) this.addEventListener('load', () => {
                  try { deliver(this.responseType === 'json' ? this.response : JSON.parse(this.responseText)); }
                  catch (_) {}
                }, {once: true});
                return result;
              };
            })();
    """.trimIndent()
}

class WdttCaptchaActivity : Activity() {
    private var challenge: WdttCaptcha.Challenge? = null
    private var webView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val request = WdttCaptcha.current ?: return finish()
        challenge = request
        request.activity = this
        webView = WdttCaptcha.createWebView(this, request).also { view ->
            setContentView(view)
            view.loadUrl(request.url)
        }
    }

    override fun onDestroy() {
        webView?.destroy()
        if (challenge?.activity === this && !isChangingConfigurations) {
            challenge?.result?.complete("error:cancelled")
        }
        super.onDestroy()
    }
}
