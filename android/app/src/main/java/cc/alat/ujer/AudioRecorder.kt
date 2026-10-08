package cc.alat.ujer

import android.media.MediaRecorder
import java.io.File

class AudioRecorder {
    private var recorder: MediaRecorder? = null

    fun start(file: File) {
        check(recorder == null)
        recorder = MediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(16_000)
            setAudioEncodingBitRate(64_000)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
    }

    fun stop() {
        recorder?.runCatching { stop() }
        recorder?.release()
        recorder = null
    }
}
