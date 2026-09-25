import Foundation
import Security

struct PrivateSyncSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let userID: String
    let email: String
}

protocol PrivateSyncSessionStoring: Sendable {
    func load() throws -> PrivateSyncSession?
    func save(_ session: PrivateSyncSession) throws
    func clear() throws
}

enum PrivateSyncBridgeError: LocalizedError {
    case invalidConfiguration
    case invalidCredentials
    case signedOut
    case noSnapshot
    case invalidSnapshot
    case requestFailed(String)
    case keychain

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Private Sync configuration is unavailable."
        case .invalidCredentials: "The Private Sync email or password was not accepted."
        case .signedOut: "Connect the same owner account used by Daily Routine on iPhone."
        case .noSnapshot: "The iPhone has not published a Personal Systems Agent snapshot yet. Open Daily Routine on iPhone while Private Sync is connected."
        case .invalidSnapshot: "The privacy-limited Daily Routine snapshot was not recognized."
        case .requestFailed(let message): message
        case .keychain: "The Private Sync session could not be stored securely in Keychain."
        }
    }
}

final class KeychainPrivateSyncSessionStore: PrivateSyncSessionStoring, @unchecked Sendable {
    private let service = "com.bojangles4x4.DailyRoutine.agent.private-sync"
    private let account = "owner-session"

    func load() throws -> PrivateSyncSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PrivateSyncBridgeError.keychain }
        do { return try JSONDecoder().decode(PrivateSyncSession.self, from: data) }
        catch { throw PrivateSyncBridgeError.keychain }
    }

    func save(_ session: PrivateSyncSession) throws {
        let data = try JSONEncoder().encode(session)
        try? clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw PrivateSyncBridgeError.keychain }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PrivateSyncBridgeError.keychain }
    }
}

struct FetchedPrivateSyncSnapshot: Sendable {
    let payload: Data
    let updatedAt: Date?
    let revision: Int
}

final class PrivateSyncAgentClient: @unchecked Sendable {
    static let projectURL = URL(string: "https://shmvxujnlbolgcjwwewe.supabase.co")!
    static let publishableKey = "sb_publishable_mEmMzinbOkd2FGpmSqPlmg_S6tUfqzh"

    private let projectURL: URL
    private let publishableKey: String
    private let sessionStore: PrivateSyncSessionStoring
    private let urlSession: URLSession

    init(
        projectURL: URL = PrivateSyncAgentClient.projectURL,
        publishableKey: String = PrivateSyncAgentClient.publishableKey,
        sessionStore: PrivateSyncSessionStoring = KeychainPrivateSyncSessionStore(),
        urlSession: URLSession = .shared
    ) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.sessionStore = sessionStore
        self.urlSession = urlSession
    }

    var savedAccountEmail: String? { try? sessionStore.load()?.email }
    var hasSavedSession: Bool { (try? sessionStore.load()) != nil }

    func signIn(email: String, password: String) async throws -> PrivateSyncSession {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else { throw PrivateSyncBridgeError.invalidCredentials }
        let response = try await authRequest(
            path: "/auth/v1/token?grant_type=password",
            body: ["email": normalizedEmail, "password": password],
            invalidCredentialsOnUnauthorized: true
        )
        let session = try decodeSession(response, fallback: nil)
        try sessionStore.save(session)
        return session
    }

    func signOut() async {
        if let session = try? sessionStore.load() {
            var request = URLRequest(url: projectURL.appendingPathComponent("auth/v1/logout"))
            request.httpMethod = "POST"
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        try? sessionStore.clear()
    }

    func fetchAgentSnapshot() async throws -> FetchedPrivateSyncSnapshot {
        let session = try await validSession()
        var components = URLComponents(url: projectURL.appendingPathComponent("rest/v1/agent_snapshots"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "owner_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "select", value: "schema_version,revision,payload,updated_at"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { throw PrivateSyncBridgeError.invalidConfiguration }
        let data = try await request(url: url, method: "GET", token: session.accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PrivateSyncBridgeError.invalidSnapshot
        }
        guard let row = rows.first else { throw PrivateSyncBridgeError.noSnapshot }
        guard
            let payload = row["payload"] as? [String: Any],
            (row["schema_version"] as? NSNumber)?.intValue == 1,
            payload["scope"] as? String == "routine-definitions-and-completion-signals",
            payload["state"] is [String: Any]
        else {
            throw PrivateSyncBridgeError.invalidSnapshot
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let updatedAt = (row["updated_at"] as? String).flatMap(Self.parseDate)
        return FetchedPrivateSyncSnapshot(
            payload: payloadData,
            updatedAt: updatedAt,
            revision: (row["revision"] as? NSNumber)?.intValue ?? 0
        )
    }

    private func validSession() async throws -> PrivateSyncSession {
        guard let saved = try sessionStore.load() else { throw PrivateSyncBridgeError.signedOut }
        guard saved.expiresAt <= Date().timeIntervalSince1970 + 60 else { return saved }
        let response = try await authRequest(
            path: "/auth/v1/token?grant_type=refresh_token",
            body: ["refresh_token": saved.refreshToken],
            invalidCredentialsOnUnauthorized: false
        )
        let refreshed = try decodeSession(response, fallback: saved)
        try sessionStore.save(refreshed)
        return refreshed
    }

    private func authRequest(path: String, body: [String: String], invalidCredentialsOnUnauthorized: Bool) async throws -> [String: Any] {
        guard let url = URL(string: projectURL.absoluteString + path) else { throw PrivateSyncBridgeError.invalidConfiguration }
        let data = try await request(
            url: url,
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            invalidCredentialsOnUnauthorized: invalidCredentialsOnUnauthorized
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PrivateSyncBridgeError.requestFailed("Private Sync returned an unexpected response.")
        }
        return object
    }

    private func request(
        url: URL,
        method: String,
        token: String? = nil,
        body: Data? = nil,
        invalidCredentialsOnUnauthorized: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PrivateSyncBridgeError.requestFailed("Private Sync could not be reached.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if invalidCredentialsOnUnauthorized && [400, 401].contains(http.statusCode) {
                throw PrivateSyncBridgeError.invalidCredentials
            }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["message"] ?? $0["error_description"] ?? $0["error"]) as? String }
            throw PrivateSyncBridgeError.requestFailed(String((message ?? "Private Sync request failed (\(http.statusCode)).").prefix(240)))
        }
        return data
    }

    private func decodeSession(_ response: [String: Any], fallback: PrivateSyncSession?) throws -> PrivateSyncSession {
        guard
            let accessToken = response["access_token"] as? String,
            let refreshToken = (response["refresh_token"] as? String) ?? fallback?.refreshToken
        else { throw PrivateSyncBridgeError.invalidCredentials }
        let user = response["user"] as? [String: Any]
        guard let userID = (user?["id"] as? String) ?? fallback?.userID else {
            throw PrivateSyncBridgeError.invalidCredentials
        }
        let expiresAt = (response["expires_at"] as? NSNumber)?.doubleValue
            ?? Date().timeIntervalSince1970 + ((response["expires_in"] as? NSNumber)?.doubleValue ?? 3_600)
        return PrivateSyncSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userID: userID,
            email: (user?["email"] as? String) ?? fallback?.email ?? ""
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

struct PrivateSyncSnapshotFileStore: Sendable {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Daily Routine Agent", isDirectory: true)
        .appendingPathComponent("private-sync-agent-snapshot.json")) {
        self.fileURL = fileURL
    }

    func write(_ data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["scope"] as? String == "routine-definitions-and-completion-signals",
            root["state"] is [String: Any]
        else { throw PrivateSyncBridgeError.invalidSnapshot }
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".private-sync-agent-\(UUID().uuidString).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw PrivateSyncBridgeError.invalidSnapshot
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
