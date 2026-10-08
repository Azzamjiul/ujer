package cc.alat.ujer

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private enum class DictationAction(val title: String) {
    NONE(""),
    SETUP("OPEN SETTINGS"),
    ALLOW_MICROPHONE("ALLOW MICROPHONE"),
    OPEN_APP_SETTINGS("OPEN APP SETTINGS"),
    RECORD_AGAIN("RECORD AGAIN"),
}

class DictationActivity : ComponentActivity() {
    private val store by lazy { SettingsStore(this) }
    private val recorder = AudioRecorder()
    private var recordingFile: File? = null
    private var status by mutableStateOf("PREPARING")
    private var detail by mutableStateOf("")
    private var recording by mutableStateOf(false)
    private var action by mutableStateOf(DictationAction.NONE)

    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startRecording() else {
            status = "MICROPHONE ACCESS REQUIRED"
            detail = "Allow microphone access for Ujer in Android app settings to dictate."
            action = DictationAction.OPEN_APP_SETTINGS
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            UjerTheme {
                RecordingScreen(status, detail, recording, action, ::stopRecording, ::runAction, ::cancel)
            }
        }
        prepareDictation()
    }

    private fun prepareDictation() {
        if (!checkConfiguration()) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startRecording()
        } else {
            status = "MICROPHONE ACCESS NEEDED"
            detail = "Ujer only records after you start dictation, then uses the audio to create text."
            action = DictationAction.ALLOW_MICROPHONE
        }
    }

    private fun checkConfiguration(): Boolean {
        val settings = store.settings()
        val valid = try {
            EndpointConfiguration(settings.baseUrl, settings.model)
            true
        } catch (_: Exception) {
            false
        }
        if (!valid) {
            status = "CHECK YOUR PROVIDER SETTINGS"
            detail = "The Base URL or model is invalid. Update it in Ujer Settings before dictating."
            action = DictationAction.SETUP
            return false
        }
        if (store.token(settings.provider).isNullOrBlank()) {
            status = "SET UP UJER FIRST"
            detail = "Add your provider API token in Ujer Settings to start dictating."
            action = DictationAction.SETUP
            return false
        }
        return true
    }

    private fun startRecording() {
        if (!checkConfiguration()) return
        try {
            recordingFile = File.createTempFile("ujer-", ".m4a", cacheDir)
            recorder.start(recordingFile!!)
            recording = true
            status = "LISTENING"
            detail = "Tap Stop when you're done speaking."
            action = DictationAction.NONE
        } catch (error: Exception) {
            recordingFile?.delete()
            recordingFile = null
            status = "COULD NOT START RECORDING"
            detail = error.message ?: "Check microphone access and try again."
            action = DictationAction.RECORD_AGAIN
        }
    }

    private fun stopRecording() {
        val file = recordingFile ?: return
        recorder.stop()
        recording = false
        status = "TRANSCRIBING"
        detail = "Turning your speech into text…"
        lifecycleScope.launch {
            try {
                val transcript = withContext(Dispatchers.IO) {
                    val settings = store.settings()
                    TranscriptionClient.transcribe(file, settings, store.token(settings.provider)!!)
                }
                check(transcript.isNotBlank()) { "No speech was detected. Record again and speak closer to the microphone." }
                (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                    .setPrimaryClip(ClipData.newPlainText("Ujer transcript", transcript))
                status = "COPIED TO CLIPBOARD"
                detail = "Paste it from your keyboard's clipboard panel."
                delay(2_000)
                finish()
            } catch (error: Exception) {
                status = "TRANSCRIPTION FAILED"
                detail = error.message ?: "Check your connection and record again."
                action = DictationAction.RECORD_AGAIN
            } finally {
                file.delete()
                recordingFile = null
            }
        }
    }

    private fun runAction() {
        when (action) {
            DictationAction.SETUP -> {
                startActivity(Intent(this, MainActivity::class.java))
                finish()
            }
            DictationAction.ALLOW_MICROPHONE -> permission.launch(Manifest.permission.RECORD_AUDIO)
            DictationAction.OPEN_APP_SETTINGS -> {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
                )
                finish()
            }
            DictationAction.RECORD_AGAIN -> prepareDictation()
            DictationAction.NONE -> Unit
        }
    }

    private fun cancel() {
        recorder.stop()
        recordingFile?.delete()
        recordingFile = null
        finish()
    }

    override fun onDestroy() {
        recorder.stop()
        recordingFile?.delete()
        super.onDestroy()
    }
}

@Composable
private fun RecordingScreen(
    status: String,
    detail: String,
    recording: Boolean,
    action: DictationAction,
    stop: () -> Unit,
    runAction: () -> Unit,
    done: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(
                modifier = Modifier.padding(horizontal = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Text("UJER", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                Text(status, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                if (detail.isNotBlank()) {
                    Text(
                        detail,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
                if (recording || status == "TRANSCRIBING") {
                    Button(
                        onClick = stop,
                        enabled = recording,
                        shape = CircleShape,
                        modifier = Modifier.size(180.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                        ),
                    ) {
                        Text(if (recording) "STOP" else "…", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                    }
                }
                if (action != DictationAction.NONE) {
                    Button(onClick = runAction) { Text(action.title) }
                    TextButton(onClick = done) { Text("CANCEL") }
                } else if (status == "COPIED TO CLIPBOARD") {
                    TextButton(onClick = done) { Text("DONE") }
                } else if (recording || status == "TRANSCRIBING") {
                    TextButton(onClick = done) { Text("CANCEL") }
                }
            }
        }
    }
}
