package cc.alat.ujer

import org.json.JSONObject
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.util.UUID

object TranscriptionClient {
    private const val maximumFileSize = 25_000_000L

    fun transcribe(file: File, settings: ProviderSettings, token: String): String {
        require(file.length() <= maximumFileSize) { "Recording is too large." }
        val config = EndpointConfiguration(settings.baseUrl, settings.model)
        return when (settings.provider) {
            Provider.OPENAI_COMPATIBLE -> openAiCompatible(file, config, token)
            Provider.DEEPGRAM -> deepgram(file, config, token)
        }
    }

    private fun openAiCompatible(file: File, config: EndpointConfiguration, token: String): String {
        val boundary = "Ujer-${UUID.randomUUID()}"
        return request(config, config.endpoint("audio/transcriptions"), "Bearer $token", "multipart/form-data; boundary=$boundary") { output ->
            DataOutputStream(output).use { body ->
                body.writeUtf8("--$boundary\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n${config.model}\r\n")
                body.writeUtf8("--$boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n")
                file.inputStream().use { it.copyTo(body) }
                body.writeUtf8("\r\n--$boundary--\r\n")
            }
        }.let(::parseOpenAi)
    }

    private fun deepgram(file: File, config: EndpointConfiguration, token: String): String =
        request(config, config.endpoint("listen", mapOf("model" to config.model, "punctuate" to "true")), "Token $token", "audio/mp4") { output ->
            file.inputStream().use { input -> input.copyTo(output) }
        }.let(::parseDeepgram)

    private fun request(
        config: EndpointConfiguration,
        initialUrl: URI,
        authorization: String,
        contentType: String,
        write: (java.io.OutputStream) -> Unit,
    ): String {
        var url = initialUrl
        repeat(4) {
            val connection = (url.toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                instanceFollowRedirects = false
                connectTimeout = 60_000
                readTimeout = 75_000
                doOutput = true
                setRequestProperty("Authorization", authorization)
                setRequestProperty("Content-Type", contentType)
            }
            try {
                connection.outputStream.use(write)
                when (connection.responseCode) {
                    in 200..299 -> return connection.inputStream.bufferedReader().use { it.readText() }
                    in 300..399 -> {
                        val redirect = connection.getHeaderField("Location")?.let { url.resolve(it) }
                        require(redirect != null && config.sameOrigin(redirect)) { "Transcription endpoint redirected to another origin." }
                        url = redirect
                    }
                    else -> throw IllegalStateException("Transcription endpoint returned HTTP ${connection.responseCode}.")
                }
            } finally {
                connection.disconnect()
            }
        }
        error("Too many redirects from transcription endpoint.")
    }

    private fun DataOutputStream.writeUtf8(value: String) = write(value.toByteArray(Charsets.UTF_8))

    internal fun parseOpenAi(body: String): String =
        JSONObject(body).optString("text").trim().also { require(it.isNotEmpty()) { "No speech was transcribed." } }

    internal fun parseDeepgram(body: String): String =
        JSONObject(body).getJSONObject("results").getJSONArray("channels").getJSONObject(0)
            .getJSONArray("alternatives").getJSONObject(0).optString("transcript").trim()
            .also { require(it.isNotEmpty()) { "No speech was transcribed." } }
}
