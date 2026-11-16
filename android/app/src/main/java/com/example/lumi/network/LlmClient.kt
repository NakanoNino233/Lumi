package com.example.lumi.network

import com.example.lumi.BuildConfig
import com.example.lumi.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.atomic.AtomicReference

data class Turn(val role: String, val content: String, val image: String = "")
data class Completion(val text: String, val input: Long = 0, val output: Long = 0)

object Endpoint {
    fun resolve(base: String, protocol: String = "openai", allowLocal: Boolean = false): String {
        val uri = runCatching { URI(base.trim()) }.getOrElse { throw IllegalArgumentException("服务地址格式不正确") }
        val local = uri.host in setOf("localhost", "127.0.0.1", "10.0.2.2")
        require((uri.scheme == "https" || (allowLocal && local && uri.scheme == "http")) && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null) { "请填写 HTTPS 服务地址，不带账号、查询参数或片段" }
        val path = uri.path.orEmpty().trimEnd('/')
        val suffix = if (protocol == "anthropic") "/messages" else "/chat/completions"
        val target = when {
            path.endsWith(suffix) -> path
            protocol == "anthropic" && path.isBlank() -> "/v1/messages"
            protocol != "anthropic" && uri.host == "api.openai.com" && path.isBlank() -> "/v1/chat/completions"
            else -> path + suffix
        }
        return URI(uri.scheme, null, uri.host, uri.port, target, null, null).toString()
    }
}

/** Bounded SSE framing. CRLF, comments, multiple data lines, and arbitrary chunk boundaries are supported. */
class SseDecoder(private val onEvent: (String) -> Unit) {
    private val line = StringBuilder()
    private val data = mutableListOf<String>()
    private var size = 0
    private var cr = false
    fun append(chunk: String) {
        chunk.forEach { c ->
            if (c == '\n' && cr) { cr = false; return@forEach }
            when (c) {
                '\r', '\n' -> { consumeLine(); cr = c == '\r' }
                else -> { cr = false; line.append(c); require(line.length + size <= 1_048_576) { "服务响应过大" } }
            }
        }
    }
    fun finish() { if (line.isNotEmpty()) consumeLine(); dispatch() }
    private fun consumeLine() {
        val value = line.toString(); line.setLength(0)
        if (value.isEmpty()) dispatch()
        else if (value.startsWith("data:")) {
            val piece = value.substring(5).removePrefix(" ")
            size += piece.length
            require(size <= 1_048_576) { "服务响应过大" }; data.add(piece)
        }
    }
    private fun dispatch() { if (data.isNotEmpty()) { val value = data.joinToString("\n"); data.clear(); size = 0; onEvent(value) } }
}

class LlmCall {
    private val connection = AtomicReference<HttpURLConnection?>()
    @Volatile private var cancelled = false
    fun cancel() { cancelled = true; connection.getAndSet(null)?.disconnect() }

    suspend fun run(provider: Provider, key: String, turns: List<Turn>, stream: Boolean = true, onDelta: (String) -> Unit = {}): Completion = withContext(Dispatchers.IO) {
        require(key.isNotBlank()) { "请先在「我的 → API 配置」填写 API Key" }
        require(provider.model.isNotBlank()) { "请填写模型名称" }
        require(!key.contains('\n') && !key.contains('\r')) { "API Key 不能包含换行" }
        val endpoint = Endpoint.resolve(provider.baseUrl, provider.protocol, BuildConfig.DEBUG)
        val anthropic = provider.protocol == "anthropic"
        val body = json("model" to provider.model.trim(), "stream" to stream)
        val messages = JSONArray()
        val system = turns.filter { it.role == "system" }.joinToString("\n\n") { it.content }
        if (anthropic) body.put("system", system).put("max_tokens", 2048)
        else {
            if (system.isNotBlank()) messages.put(json("role" to "system", "content" to system))
            if (URI(endpoint).host == "api.openai.com") body.put("max_completion_tokens", 2048)
            else body.put("max_tokens", 2048)
        }
        for (turn in turns.filter { it.role != "system" }) {
            var content: Any = turn.content
            if (turn.image.isNotEmpty()) {
                require(provider.vision) { "当前配置未启用图片理解，请在 API 配置中开启并确认模型支持" }
                content = if (anthropic) arr(listOf(
                    json("type" to "image", "source" to json("type" to "base64", "media_type" to "image/jpeg", "data" to turn.image)),
                    json("type" to "text", "text" to turn.content.ifBlank { "请看看这张图片" })))
                else arr(listOf(json("type" to "text", "text" to turn.content.ifBlank { "请看看这张图片" }),
                    json("type" to "image_url", "image_url" to json("url" to "data:image/jpeg;base64,${turn.image}"))))
            }
            messages.put(json("role" to turn.role, "content" to content))
        }
        body.put("messages", messages)
        currentCoroutineContext().ensureActive()
        check(!cancelled) { "请求已停止" }
        val conn = URI(endpoint).toURL().openConnection() as HttpURLConnection
        connection.set(conn)
        try {
            conn.instanceFollowRedirects = false
            conn.requestMethod = "POST"; conn.doOutput = true
            conn.connectTimeout = 20_000; conn.readTimeout = 90_000
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.setRequestProperty("Accept", if (stream) "text/event-stream" else "application/json")
            if (anthropic) { conn.setRequestProperty("x-api-key", key.trim()); conn.setRequestProperty("anthropic-version", "2023-06-01") }
            else conn.setRequestProperty("Authorization", "Bearer ${key.trim()}")
            val bytes = body.toString().toByteArray(Charsets.UTF_8)
            conn.setFixedLengthStreamingMode(bytes.size)
            check(!cancelled) { "请求已停止" }
            conn.outputStream.use { it.write(bytes) }
            val code = conn.responseCode
            if (code !in 200..299) throw IllegalStateException(when(code) {
                401, 403 -> "鉴权失败（HTTP $code），请检查 API Key 和模型权限"
                404 -> "找不到接口或模型（HTTP 404），请检查服务地址和模型名"
                429 -> "请求受限或额度不足（HTTP 429），请稍后重试或检查账户"
                in 300..399 -> "服务返回重定向，已停止转发密钥，请填写最终接口地址"
                else -> "模型服务返回 HTTP $code，请稍后重试"
            })
            val output = StringBuilder(); var inputTokens = 0L; var outputTokens = 0L; var terminal = false; var streamDone = false
            fun usage(obj: JSONObject?) {
                obj ?: return
                inputTokens = maxOf(inputTokens, obj.optLong("prompt_tokens", obj.optLong("input_tokens")))
                outputTokens = maxOf(outputTokens, obj.optLong("completion_tokens", obj.optLong("output_tokens")))
            }
            fun append(text: String) {
                output.append(text); require(output.length <= 128_000) { "回复过长，已停止接收" }
                onDelta(text)
            }
            if (conn.contentType.orEmpty().contains("text/event-stream", true)) {
                val decoder = SseDecoder { event ->
                    if (event.trim() == "[DONE]") { terminal = true; streamDone = true }
                    else if (event.trimStart().startsWith("{")) {
                        val o = JSONObject(event)
                        require(!o.has("error") && o.text("type") != "error") { "模型返回错误，请检查模型配置或账户额度" }
                        usage(o.optJSONObject("usage")); usage(o.optJSONObject("message")?.optJSONObject("usage"))
                        if (anthropic) {
                            if (o.text("type") == "content_block_delta" && o.optJSONObject("delta")?.text("type") == "text_delta") append(o.getJSONObject("delta").text("text"))
                            if (o.text("type") == "message_stop") { terminal = true; streamDone = true }
                        } else {
                            val choice = o.optJSONArray("choices")?.optJSONObject(0)
                            val delta = choice?.optJSONObject("delta")
                            if (delta != null && !delta.isNull("content")) append(delta.text("content"))
                            if (choice != null && !choice.isNull("finish_reason") && choice.text("finish_reason").isNotBlank()) terminal = true
                        }
                    }
                }
                conn.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    val buffer = CharArray(2048)
                    while (!streamDone) {
                        currentCoroutineContext().ensureActive(); check(!cancelled) { "请求已停止" }
                        val count = reader.read(buffer); if (count < 0) break
                        decoder.append(String(buffer, 0, count))
                    }
                    decoder.finish()
                }
                require(terminal) { "连接提前中断，已保留收到的内容，可以重新生成" }
            } else {
                val raw = StringBuilder()
                conn.inputStream.bufferedReader(Charsets.UTF_8).use { reader ->
                    val buffer = CharArray(2048)
                    while (true) { currentCoroutineContext().ensureActive(); val n = reader.read(buffer); if (n < 0) break; raw.append(buffer, 0, n); require(raw.length <= 1_048_576) { "服务响应过大" } }
                }
                val o = JSONObject(raw.toString()); require(!o.has("error")) { "模型返回错误，请检查配置" }; usage(o.optJSONObject("usage"))
                val text = if (anthropic) o.objects("content").filter { it.text("type") == "text" }.joinToString("") { it.text("text") }
                else o.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.text("content").orEmpty()
                append(text)
            }
            require(output.isNotBlank()) { "服务没有返回文字，请检查模型是否支持聊天" }
            Completion(output.toString(), inputTokens, outputTokens)
        } finally { connection.compareAndSet(conn, null); conn.disconnect() }
    }
}

fun visibleReply(raw: String): String = raw.replace(Regex("<meta\\b[^>]*(?:>|$)", RegexOption.IGNORE_CASE), "")
    .replace(Regex("<mem\\b[^>]*(?:>|$)", RegexOption.IGNORE_CASE), "").trim()

fun friendlyError(error: Throwable): String = when (error) {
    is java.net.SocketTimeoutException -> "连接超时，请检查网络后重试"
    is java.net.UnknownHostException -> "无法解析服务地址，请检查网络和 API 地址"
    is javax.net.ssl.SSLException -> "HTTPS 连接失败，请检查服务证书和手机时间"
    is java.io.IOException -> "网络连接中断，请检查网络后重试"
    is IllegalArgumentException, is IllegalStateException -> error.message ?: "请求失败，请检查配置"
    else -> "无法完成请求，请检查配置后重试"
}
