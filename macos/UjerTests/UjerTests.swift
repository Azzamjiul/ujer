import Carbon
import XCTest
@testable import Ujer

final class UjerTests: XCTestCase {
    func testDictationStateTransitions() {
        XCTAssertTrue(DictationPhase.idle.canTransition(to: .preparing))
        XCTAssertTrue(DictationPhase.preparing.canTransition(to: .error))
        XCTAssertTrue(DictationPhase.recording.canTransition(to: .transcribing))
        XCTAssertTrue(DictationPhase.transcribing.canTransition(to: .done))
        XCTAssertTrue(DictationPhase.error.canTransition(to: .transcribing))
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

    func testDeepgramEndpointUsesListenPath() throws {
        let configuration = try EndpointConfiguration(
            baseURL: "https://api.deepgram.com/v1",
            model: "nova-3",
            provider: .deepgram
        )
        XCTAssertEqual(configuration.transcriptionURL.absoluteString, "https://api.deepgram.com/v1/listen")
        XCTAssertEqual(
            try EndpointConfiguration(baseURL: "https://api.deepgram.com", model: "nova-3", provider: .deepgram).transcriptionURL.absoluteString,
            "https://api.deepgram.com/v1/listen"
        )
        XCTAssertEqual(
            try EndpointConfiguration(baseURL: "https://api.deepgram.com/v1/listen", model: "nova-3", provider: .deepgram).transcriptionURL.absoluteString,
            "https://api.deepgram.com/v1/listen"
        )
    }

    func testConnectionTestPaths() throws {
        XCTAssertEqual(
            try EndpointConfiguration(baseURL: "https://api.openai.com/v1", model: "gpt-transcribe").connectionTestURL.absoluteString,
            "https://api.openai.com/v1/models"
        )
        XCTAssertEqual(
            try EndpointConfiguration(baseURL: "https://api.deepgram.com/v1/listen", model: "nova-3", provider: .deepgram).connectionTestURL.absoluteString,
            "https://api.deepgram.com/v1/projects"
        )
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
    func testTranscriptionResponse() throws {
        XCTAssertEqual(try JSONDecoder().decode(TranscriptionResponse.self, from: Data(#"{"text":"halo"}"#.utf8)).text, "halo")
    }

    func testDeepgramResponse() throws {
        let data = Data(#"{"results":{"channels":[{"alternatives":[{"transcript":"halo dunia"}]}]}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DeepgramResponse.self, from: data).transcript, "halo dunia")
    }

    func testKeychainRoundTrip() throws {
        let account = "test-\(UUID().uuidString)"
        defer { try? Keychain.delete(account: account) }
        try Keychain.save("test-token", account: account)
        XCTAssertEqual(try Keychain.read(account: account), "test-token")
    }
}
