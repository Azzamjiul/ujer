import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

enum DictationPhase: Equatable, Sendable {
    case idle
    case preparing
    case recording
    case transcribing
    case done
    case error

    func canTransition(to next: DictationPhase) -> Bool {
        switch (self, next) {
        case (.idle, .preparing),
             (.preparing, .recording), (.preparing, .idle), (.preparing, .error),
             (.recording, .transcribing), (.recording, .idle), (.recording, .error),
             (.transcribing, .done), (.transcribing, .error),
             (.done, .idle), (.error, .idle):
            true
        default:
            false
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "waveform.badge.mic"
        case .preparing: "waveform.badge.mic"
        case .recording: "mic.and.signal.meter"
        case .transcribing: "waveform.circle"
        case .done: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var label: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .done: "Done"
        case .error: "Error"
        }
    }
}

private struct DictationSession {
    let id = UUID()
    let target: FocusTarget
    let fileURL: URL
    let configuration: EndpointConfiguration
    let token: String
}

@main
struct UjerApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = AudioRecorder()
    private lazy var recordingHUD = RecordingHUD(
        level: { [weak self] in self?.recorder.meterLevel ?? 0 },
        onStop: { [weak self] in self?.stopDictation() }
    )
    private let settings = SettingsStore()
    private let globalHotkey = GlobalHotkey()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var phase = DictationPhase.idle
    private var session: DictationSession?
    private var preparationTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var message = ""
    private var microphonePermissionDenied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemPressed)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        if let error = setGlobalHotkey(settings.hotkey) {
            message = error
        }
        renderStatus()
    }

    @objc private func statusItemPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        switch phase {
        case .idle:
            startDictation()
        case .recording:
            stopDictation()
        case .preparing:
            cancelPreparation()
        default:
            NSSound.beep()
        }
    }

    @objc func hotkeyPressed() {
        switch phase {
        case .idle:
            startDictation()
        case .recording:
            stopDictation()
        case .preparing:
            cancelPreparation()
        default:
            NSSound.beep()
        }
    }

    @objc private func openSettings() {
        let controller = NSHostingController(rootView: SettingsView(settings: settings, setHotkey: setGlobalHotkey))
        let window = NSWindow(contentViewController: controller)
        window.title = "Ujer Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 380))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        cleanupSession()
        NSApp.terminate(nil)
    }

    private func setGlobalHotkey(_ shortcut: Hotkey) -> String? {
        do {
            try globalHotkey.replace(with: shortcut)
            settings.saveHotkey(shortcut)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let status = menu.addItem(withTitle: phase.label + (message.isEmpty ? "" : ": \(message)"), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(NSMenuItem.separator())
        if microphonePermissionDenied {
            let microphoneItem = menu.addItem(withTitle: "Open Microphone Settings…", action: #selector(openMicrophoneSettings), keyEquivalent: "")
            microphoneItem.target = self
        }
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let quitItem = menu.addItem(withTitle: "Quit Ujer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func startDictation() {
        resetTask?.cancel()
        message = ""
        microphonePermissionDenied = false
        transition(to: .preparing)
        preparationTask = Task { @MainActor [weak self] in
            await self?.prepareAndRecord()
        }
    }

    private func prepareAndRecord() async {
        do {
            let microphoneAllowed = await microphoneAllowed()
            guard phase == .preparing, !Task.isCancelled else { return }
            guard microphoneAllowed else {
                microphonePermissionDenied = true
                fail(RecorderError.permissionDenied)
                return
            }
            let configuration = try settings.configuration()
            guard let token = try settings.token() else { throw UjerError.missingToken }
            guard FocusInjector.requestAccessibilityTrust() else { throw AccessibilityError.notTrusted }
            let target = try FocusInjector.capture()

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ujer-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let active = DictationSession(target: target, fileURL: fileURL, configuration: configuration, token: token)
            session = active
            try recorder.start(to: fileURL)
            recordingHUD.show()
            preparationTask = nil
            transition(to: .recording)
            scheduleTimeout(for: active.id)
        } catch {
            fail(error)
        }
    }

    private func stopDictation() {
        guard phase == .recording, let active = session else { return }
        recordingHUD.hide()
        timeoutTask?.cancel()
        timeoutTask = nil
        recorder.stop()
        transition(to: .transcribing)
        transcriptionTask = Task { @MainActor [weak self] in
            do {
                let transcript = try await TranscriptionClient.transcribe(
                    fileURL: active.fileURL,
                    configuration: active.configuration,
                    token: active.token
                )
                guard let self, self.session?.id == active.id else { return }
                self.transcriptionTask = nil
                self.finish(transcript: transcript, session: active)
            } catch {
                guard let self, self.session?.id == active.id else { return }
                self.transcriptionTask = nil
                self.fail(error)
            }
        }
    }

    private func finish(transcript: String, session active: DictationSession) {
        cleanupSession()
        if settings.autoInsert {
            switch FocusInjector.insert(transcript, into: active.target) {
            case .inserted:
                message = ""
                transition(to: .done)
            case .copiedOnly(let reason):
                message = reason
                transition(to: .error)
            }
        } else {
            FocusInjector.copy(transcript)
            message = "Transcript copied."
            transition(to: .done)
        }
        scheduleReset()
    }

    private func cancelPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        cleanupSession()
        transition(to: .idle)
    }

    private func fail(_ error: Error) {
        cleanupSession()
        message = error.localizedDescription
        if phase != .error {
            transition(to: .error)
        }
        scheduleReset()
    }

    private func cleanupSession() {
        recordingHUD.hide()
        preparationTask?.cancel()
        preparationTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        recorder.stop()
        if let fileURL = session?.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        session = nil
    }

    private func scheduleTimeout(for id: UUID) {
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard !Task.isCancelled, self?.session?.id == id else { return }
            self?.stopDictation()
        }
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .done || self.phase == .error else { return }
            self.message = ""
            self.transition(to: .idle)
        }
    }

    private func transition(to next: DictationPhase) {
        guard phase.canTransition(to: next) else {
            assertionFailure("Invalid dictation transition \(phase) -> \(next)")
            return
        }
        phase = next
        renderStatus()
    }

    private func renderStatus() {
        statusItem.button?.image = NSImage(
            systemSymbolName: phase.symbolName,
            accessibilityDescription: "Ujer \(phase.label)"
        )
        statusItem.button?.toolTip = message.isEmpty ? "Ujer: \(phase.label)" : "Ujer: \(message)"
    }

    private func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default: return false
        }
    }

    @objc private func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var baseURL: String
    @Published var model: String
    @Published var autoInsert: Bool
    @Published var hotkey: Hotkey
    @Published private(set) var launchAtLogin: Bool

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "baseURL": "https://api.openai.com/v1",
            "model": "gpt-transcribe",
            "autoInsert": true,
            "hotkeyKeyCode": Int(Hotkey.defaultValue.keyCode),
            "hotkeyModifiers": Int(Hotkey.defaultValue.modifiers),
        ])
        baseURL = defaults.string(forKey: "baseURL")!
        model = defaults.string(forKey: "model")!
        autoInsert = defaults.bool(forKey: "autoInsert")
        hotkey = Hotkey(keyCode: UInt32(defaults.integer(forKey: "hotkeyKeyCode")), modifiers: UInt32(defaults.integer(forKey: "hotkeyModifiers")))
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func save(token: String) throws {
        UserDefaults.standard.set(baseURL, forKey: "baseURL")
        UserDefaults.standard.set(model, forKey: "model")
        UserDefaults.standard.set(autoInsert, forKey: "autoInsert")
        try Keychain.save(token)
    }

    func configuration() throws -> EndpointConfiguration {
        try EndpointConfiguration(baseURL: baseURL, model: model)
    }

    func token() throws -> String? {
        try Keychain.read()
    }

    func saveHotkey(_ shortcut: Hotkey) {
        UserDefaults.standard.set(Int(shortcut.keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(shortcut.modifiers), forKey: "hotkeyModifiers")
        hotkey = shortcut
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let setHotkey: (Hotkey) -> String?
    @State private var token = ""
    @State private var notice = ""
    @State private var hotkeyNotice = ""

    var body: some View {
        Form {
            Text("OpenAI-compatible BYOK").font(.headline)
            TextField("Base URL", text: $settings.baseURL)
            TextField("Model", text: $settings.model)
            SecureField("Token", text: $token)
            Toggle("Auto-insert transcript", isOn: $settings.autoInsert)
            HStack {
                Text("Record shortcut")
                Spacer()
                HotkeyRecorder(shortcut: settings.hotkey) { shortcut in
                    if let error = setHotkey(shortcut) {
                        hotkeyNotice = error
                    } else {
                        hotkeyNotice = ""
                    }
                }
                .frame(width: 120, height: 28)
            }
            HStack {
                Button("Reset to default") {
                    if let error = setHotkey(.defaultValue) {
                        hotkeyNotice = error
                    } else {
                        hotkeyNotice = ""
                    }
                }
                if !hotkeyNotice.isEmpty {
                    Text(hotkeyNotice).foregroundStyle(.secondary)
                }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { enabled in
                    do {
                        try settings.setLaunchAtLogin(enabled)
                        notice = ""
                    } catch {
                        notice = error.localizedDescription
                    }
                }
            ))
            Button("Save settings") {
                do {
                    try settings.save(token: token)
                    notice = "Saved."
                } catch {
                    notice = error.localizedDescription
                }
            }
            if !notice.isEmpty {
                Text(notice).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear {
            token = (try? settings.token()) ?? ""
        }
    }
}
