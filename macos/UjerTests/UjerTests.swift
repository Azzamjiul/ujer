import Carbon
import XCTest
@testable import Ujer

final class UjerTests: XCTestCase {
    func testDictationStateTransitions() {
        XCTAssertTrue(DictationPhase.idle.canTransition(to: .preparing))
        XCTAssertTrue(DictationPhase.preparing.canTransition(to: .error))
        XCTAssertTrue(DictationPhase.recording.canTransition(to: .transcribing))
        XCTAssertTrue(DictationPhase.transcribing.canTransition(to: .done))
        XCTAssertFalse(DictationPhase.idle.canTransition(to: .recording))
        XCTAssertFalse(DictationPhase.done.canTransition(to: .recording))
    }

    func testHotkeyValidation() throws {
        XCTAssertEqual(Hotkey.defaultValue.title, "⇧⌘Space")
        XCTAssertThrowsError(try Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).validate())
        XCTAssertThrowsError(try Hotkey(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)).validate())
        XCTAssertThrowsError(try Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)).validate())
        XCTAssertNoThrow(try Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey | optionKey)).validate())
    }

    func testEndpointAllowsHTTPSAndLoopbackOnly() throws {
        XCTAssertEqual(
            try EndpointConfiguration(baseURL: "https://api.example.test/v1", model: "gpt-transcribe").transcriptionURL.absoluteString,
            "https://api.example.test/v1/audio/transcriptions"
        )
        XCTAssertNoThrow(try EndpointConfiguration(baseURL: "http://localhost:8080/v1", model: "local"))
        XCTAssertThrowsError(try EndpointConfiguration(baseURL: "http://example.test/v1", model: "local"))
        XCTAssertThrowsError(try EndpointConfiguration(baseURL: "https://user@example.test/v1", model: "local"))
    }

    func testRedirectRequiresSameOrigin() throws {
        let source = URL(string: "https://api.example.test/v1")!
        XCTAssertTrue(EndpointConfiguration.sameOrigin(source, URL(string: "https://api.example.test/next")!))
        XCTAssertFalse(EndpointConfiguration.sameOrigin(source, URL(string: "https://other.example.test/next")!))
        XCTAssertFalse(EndpointConfiguration.sameOrigin(source, URL(string: "http://api.example.test/next")!))
    }

    func testMultipartBodyContainsModelAndAACFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try Data([0x01, 0x02]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let body = try MultipartForm.makeBody(fileURL: file, model: "gpt-transcribe", boundary: "boundary")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\""))
        XCTAssertTrue(text.contains("gpt-transcribe"))
        XCTAssertTrue(text.contains("filename=\"dictation.m4a\""))
        XCTAssertTrue(text.contains("Content-Type: audio/mp4"))
    }

    @MainActor
    func testTranscriptionResponseAndClipboardRaceGuard() throws {
        XCTAssertEqual(try JSONDecoder().decode(TranscriptionResponse.self, from: Data(#"{"text":"halo"}"#.utf8)).text, "halo")
        XCTAssertTrue(FocusInjector.shouldRestoreClipboard(currentChangeCount: 7, ujerChangeCount: 7))
        XCTAssertFalse(FocusInjector.shouldRestoreClipboard(currentChangeCount: 8, ujerChangeCount: 7))
    }

    @MainActor
    func testClipboardSnapshotCopiesPasteboardItemData() {
        let source = NSPasteboard(name: .init("UjerTests-\(UUID().uuidString)"))
        source.clearContents()
        let item = NSPasteboardItem()
        item.setString("before", forType: .string)
        item.setData(Data([0x01, 0x02]), forType: .init("cc.alat.ujer.test"))
        source.writeObjects([item])

        let snapshot = ClipboardSnapshot(source)
        source.clearContents()
        snapshot.restore(to: source)

        let restored = source.pasteboardItems?.first
        XCTAssertEqual(restored?.string(forType: .string), "before")
        XCTAssertEqual(restored?.data(forType: .init("cc.alat.ujer.test")), Data([0x01, 0x02]))
    }

    func testKeychainRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? Keychain.delete(account: account) }
        try Keychain.save("test-token", account: account)
        XCTAssertEqual(try Keychain.read(account: account), "test-token")
    }
}
