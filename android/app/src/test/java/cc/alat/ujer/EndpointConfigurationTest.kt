package cc.alat.ujer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class EndpointConfigurationTest {
    @Test fun openAiEndpointUsesConfiguredBasePath() {
        val config = EndpointConfiguration("https://api.example.test/v1", "gpt-transcribe")
        assertEquals("https://api.example.test/v1/audio/transcriptions", config.endpoint("audio/transcriptions").toString())
    }

    @Test fun deepgramEndpointEncodesModel() {
        val config = EndpointConfiguration("https://api.deepgram.com/v1", "nova 3")
        assertEquals("https://api.deepgram.com/v1/listen?model=nova+3&punctuate=true", config.endpoint("listen", mapOf("model" to config.model, "punctuate" to "true")).toString())
    }

    @Test fun insecureAndCredentialedEndpointsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { EndpointConfiguration("http://example.test/v1", "model") }
        assertThrows(IllegalArgumentException::class.java) { EndpointConfiguration("https://user@example.test/v1", "model") }
    }

    @Test fun providerResponsesReadOnlyTheirTranscriptField() {
        assertEquals("halo", TranscriptionClient.parseOpenAi("{\"text\":\" halo \"}"))
        assertEquals(
            "halo",
            TranscriptionClient.parseDeepgram("{\"results\":{\"channels\":[{\"alternatives\":[{\"transcript\":\" halo \"}]}]}}"),
        )
    }

}
