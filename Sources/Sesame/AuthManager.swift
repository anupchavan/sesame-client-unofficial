import Foundation

enum AuthError: LocalizedError {
    case noRefreshToken
    case noAPIKey
    case exchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken: "No refresh token — add one in Settings (⌘,)"
        case .noAPIKey: "No Firebase API key — add one in Settings (⌘,)"
        case .exchangeFailed(let m): "Sign-in failed: \(m)"
        }
    }
}

/// Firebase Secure Token auth: long-lived refresh token → ~1h ID token, cached and
/// refreshed a few minutes before expiry.
final class AuthManager: @unchecked Sendable {
    static let shared = AuthManager()

    private let lock = NSLock()
    private var cachedToken: String?
    private var expiry = Date.distantPast

    /// Strips whitespace and surrounding quotes (tokens are often saved as JSON strings).
    private static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.count > 1, t.hasPrefix("\""), t.hasSuffix("\"") {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    /// Looks for a dev secret file (`secrets/<name>`) near the working directory or app bundle.
    private static func secretFile(_ name: String) -> String? {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/secrets/" + name,
            Bundle.main.bundlePath + "/../secrets/" + name,
            Bundle.main.bundlePath + "/../../secrets/" + name,
        ]
        for p in candidates {
            if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                let t = clean(s)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    /// Sesame's public Firebase client key — the same for every user (it identifies the app,
    /// not the person). Used as a fallback so users only need to supply a refresh token; they
    /// can override it in Settings if Sesame ever rotates it.
    static let defaultAPIKey = "AIzaSyDtC7Uwb5pGAsdmrH2T4Gqdk5Mga07jYPM"

    /// A key the user explicitly provided (Settings or dev file), or nil to use the default.
    var userProvidedAPIKey: String? {
        if let k = UserDefaults.standard.string(forKey: "sesameApiKey"), !Self.clean(k).isEmpty {
            return Self.clean(k)
        }
        return Self.secretFile("api_key")
    }

    var apiKey: String { userProvidedAPIKey ?? Self.defaultAPIKey }
    var isUsingDefaultAPIKey: Bool { userProvidedAPIKey == nil }

    var refreshToken: String? {
        if let t = UserDefaults.standard.string(forKey: "sesameRefreshToken"), !Self.clean(t).isEmpty {
            return Self.clean(t)
        }
        return Self.secretFile("refresh_token")
    }

    /// Static tool key (tool_static_key) — parity with the phone path; optional.
    static var staticToolKey: String? { secretFile("tool_static_key") }

    /// Only the refresh token is required now — the API key always has the built-in default.
    var hasCredentials: Bool { refreshToken != nil }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cachedToken = nil
        expiry = .distantPast
    }

    private func cachedValidToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        return expiry.timeIntervalSinceNow > 120 ? cachedToken : nil
    }

    private func storeToken(_ token: String, expiresIn: Double) {
        lock.lock(); defer { lock.unlock() }
        cachedToken = token
        expiry = Date().addingTimeInterval(expiresIn)
    }

    func validIDToken() async throws -> String {
        if let t = cachedValidToken() { return t }
        guard let refresh = refreshToken else { throw AuthError.noRefreshToken }
        let apiKey = self.apiKey  // user's, or the built-in default

        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [
            .init(name: "grant_type", value: "refresh_token"),
            .init(name: "refresh_token", value: refresh),
        ]
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.exchangeFailed("no response") }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["id_token"] as? String else {
            var msg = "HTTP \(http.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let m = err["message"] as? String {
                let apiKeyError = m.contains("API key") || m.contains("API_KEY") || m.contains("KEY_INVALID")
                switch m {
                case "INVALID_REFRESH_TOKEN": msg = "invalid refresh token"
                case "TOKEN_EXPIRED": msg = "session expired — get a fresh token"
                case "USER_DISABLED": msg = "account disabled"
                default:
                    if apiKeyError {
                        // Graceful path for when Sesame rotates the built-in key.
                        msg = isUsingDefaultAPIKey
                            ? "The built-in API key no longer works — add your own in Settings (⌘,)"
                            : "invalid API key — check it in Settings"
                    } else {
                        msg = m.replacingOccurrences(of: "_", with: " ").lowercased()
                    }
                }
            }
            throw AuthError.exchangeFailed(msg)
        }
        let expiresIn = Double((json["expires_in"] as? String) ?? "3600") ?? 3600
        storeToken(token, expiresIn: expiresIn)
        return token
    }
}
