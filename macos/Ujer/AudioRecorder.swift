import AVFoundation

enum RecorderError: LocalizedError {
    case unavailable
    case permissionDenied
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Ujer could not start the microphone."
        case .permissionDenied:
            "Microphone permission is denied. Enable Ujer in System Settings > Privacy & Security > Microphone."
        case .failed(let error):
            "Ujer could not start the microphone: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class AudioRecorder {
    static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        // 44.1 kHz is supported by the built-in mic and virtual devices more
        // consistently than forcing a 24 kHz hardware format for AAC capture.
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    private var recorder: AVAudioRecorder?

    func start(to url: URL) throws {
        do {
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecorderError.unavailable
            }
            self.recorder = recorder
        } catch let error as RecorderError {
            throw error
        } catch {
            throw RecorderError.failed(error)
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }

    var meterLevel: CGFloat {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let power = CGFloat(recorder.averagePower(forChannel: 0))
        guard power > -32 else { return 0 }
        return min(1, (power + 32) / 32)
    }
}
