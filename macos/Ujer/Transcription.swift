import Foundation
import Security

enum UjerError: LocalizedError {
    case missingToken
    case invalidEndpoint
    case insecureEndpoint
    case emptyTranscript
    case fileTooLarge
    case invalidResponse
    case serverStatus(Int)
    case requestTimedOut
    case network(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "Add a transcription token in Settings."
        case .invalidEndpoint:
            "The transcription base URL or model is invalid."
        case .insecureEndpoint:
            "Use HTTPS, except for a loopback endpoint."
        case .emptyTranscript:
            "No speech was transcribed."
        case .fileTooLarge:
            "The recording is too large to upload."
        case .invalidResponse:
            "The transcription endpoint returned an invalid response."
        case .serverStatus(let status):
            "The transcription endpoint returned HTTP \(status)."
        case .requestTimedOut:
            "Transcription timed out after 60 seconds. Check the endpoint and network connection."
        case .network(let message):
            "The transcription request failed: \(message)"
        case .keychain(let status):
            "Keychain error \(status)."
        }
    }
}

struct EndpointConfiguration: Equatable, Sendable {
    let baseURL: URL
    let model: String

    init(baseURL: String, model: String) throws {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty, trimmedModel.count <= 128,
              let components = URLComponents(string: trimmedURL),
              let url = components.url,
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw UjerError.invalidEndpoint
        }
        guard scheme == "https" || (scheme == "http" && Self.isLoopback(host)) else {
            throw UjerError.insecureEndpoint
        }
        self.baseURL = url
        self.model = trimmedModel
    }

    var transcriptionURL: URL {
        baseURL.appendingPathComponent("audio").appendingPathComponent("transcriptions")
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = URLComponents(url: lhs, resolvingAgainstBaseURL: false)
        let right = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
        return left?.scheme?.lowercased() == right?.scheme?.lowercased()
            && left?.host?.lowercased() == right?.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
    }

    private static func effectivePort(_ components: URLComponents?) -> Int? {
        guard let components else { return nil }
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

struct TranscriptionResponse: Decodable {
    let text: String
}

enum MultipartForm {
    static let maximumFileSize = 25_000_000

    static func makeBody(fileURL: URL, model: String, boundary: String) throws -> Data {
        let audio = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard audio.count <= maximumFileSize else { throw UjerError.fileTooLarge }

        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8("\(model)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\n")
        body.appendUTF8("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(value.data(using: .utf8)!)
    }
}

final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let origin: URL

    init(origin: URL) {
        self.origin = origin
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirect = request.url, EndpointConfiguration.sameOrigin(origin, redirect) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum TranscriptionClient {
    static func transcribe(
        fileURL: URL,
        configuration: EndpointConfiguration,
        token: String
    ) async throws -> String {
        let boundary = "Ujer-\(UUID().uuidString)"
        let body = try MultipartForm.makeBody(fileURL: fileURL, model: configuration.model, boundary: boundary)
        var request = URLRequest(url: configuration.transcriptionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 60
        sessionConfiguration.timeoutIntervalForResource = 75
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: SameOriginRedirectDelegate(origin: configuration.baseURL),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch let error as URLError where error.code == .timedOut {
            throw UjerError.requestTimedOut
        } catch {
            throw UjerError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UjerError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw UjerError.serverStatus(http.statusCode) }
        let text = try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw UjerError.emptyTranscript }
        return text
    }
}

enum Keychain {
    private static let service = "cc.alat.ujer"
    private static let defaultAccount = "transcription-token"

    static func read(account: String = defaultAccount) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw UjerError.keychain(status)
        }
        return token
    }

    static func save(_ token: String, account: String = defaultAccount) throws {
        if token.isEmpty {
            try delete(account: account)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw UjerError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw UjerError.keychain(updateStatus)
        }
    }

    static func delete(account: String = defaultAccount) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UjerError.keychain(status)
        }
    }
}
