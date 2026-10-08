package cc.alat.ujer

import java.net.URI
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

enum class Provider(val title: String, val defaultBaseUrl: String, val defaultModel: String) {
    OPENAI_COMPATIBLE("OpenAI-compatible", "https://api.openai.com/v1", "gpt-transcribe"),
    DEEPGRAM("Deepgram", "https://api.deepgram.com/v1", "nova-3"),
}

data class ProviderSettings(val provider: Provider, val baseUrl: String, val model: String)

class EndpointConfiguration(baseUrl: String, model: String) {
    val baseUrl: URI
    val model: String

    init {
        this.model = model.trim().also { require(it.isNotEmpty() && it.length <= 128) }
        val parsed = URI(baseUrl.trim())
        val scheme = parsed.scheme?.lowercase()
        val host = parsed.host?.lowercase()
        require(!host.isNullOrBlank() && parsed.userInfo == null && parsed.query == null && parsed.fragment == null)
        require(scheme == "https" || (scheme == "http" && isLoopback(host)))
        this.baseUrl = parsed
    }

    fun endpoint(path: String, query: Map<String, String> = emptyMap()): URI {
        val basePath = baseUrl.path.trimEnd('/')
        val queryString = query.entries.joinToString("&") {
            "${encode(it.key)}=${encode(it.value)}"
        }.ifEmpty { null }
        return URI(baseUrl.scheme, null, baseUrl.host, baseUrl.port, "$basePath/$path", queryString, null)
    }

    fun sameOrigin(other: URI): Boolean =
        baseUrl.scheme.equals(other.scheme, ignoreCase = true) &&
            baseUrl.host.equals(other.host, ignoreCase = true) &&
            effectivePort(baseUrl) == effectivePort(other)

    private fun effectivePort(uri: URI) = if (uri.port != -1) uri.port else if (uri.scheme.equals("https", true)) 443 else 80

    private fun encode(value: String) = URLEncoder.encode(value, StandardCharsets.UTF_8)

    companion object {
        private fun isLoopback(host: String) = host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
