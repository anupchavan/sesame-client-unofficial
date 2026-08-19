import Foundation
import CryptoKit
import Security

/// TOTP-style rotating access key for the personal tool endpoint, port of tool_key.py:
///   key = HMAC-SHA256(secret, floor(now / 300))  → first 10 hex chars.
/// The `tool_secret` is never stored in plaintext: it is AES-GCM encrypted with a
/// symmetric key held in the macOS Keychain, and the ciphertext lives in Application Support.
/// The static key (tool_static_key) is kept for parity with the phone path.
/// User-configurable custom tool endpoint (Advanced settings).
enum ToolConfig {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "sesameToolEnabled") }
    static var endpoint: String {
        (UserDefaults.standard.string(forKey: "sesameToolEndpoint") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Active only when switched on, an endpoint URL is set, and a shared secret exists.
    static var isActive: Bool {
        enabled && !endpoint.isEmpty && ToolKey.isConfigured
    }
}

enum ToolKey {
    static let rotateWindow: TimeInterval = 300 // 5 minutes, matches tool_key.py

    private static let keychainAccount = "com.anup.sesame.toolSecretKey"
    private static var encFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sesame", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tool_secret.enc")
    }

    /// True when a tool secret is available (encrypted store or importable dev file).
    static var isConfigured: Bool { secret() != nil }

    /// Store a user-provided shared secret (encrypted at rest). Empty clears it.
    static func setSecret(_ plain: String) {
        let t = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            try? FileManager.default.removeItem(at: encFileURL)
        } else {
            try? encryptAndStore(Data(t.utf8))
        }
    }

    // MARK: - Public key API

    static func key(forWindow w: Int) -> String? {
        guard let secret = secret() else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: Data(String(w).utf8), using: SymmetricKey(data: secret))
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(10))
    }

    static func currentKey() -> String? {
        key(forWindow: Int(Date().timeIntervalSince1970 / rotateWindow))
    }

    static var staticKey: String? {
        AuthManager.staticToolKey
    }

    /// Accepts the static key or the current/previous rotating window (constant-time).
    static func isValid(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        if let s = staticKey, constantTimeEqual(candidate, s) { return true }
        let w = Int(Date().timeIntervalSince1970 / rotateWindow)
        for x in [w, w - 1] {
            if let k = key(forWindow: x), constantTimeEqual(candidate, k) { return true }
        }
        return false
    }

    // MARK: - Encrypted secret at rest

    /// Returns the decrypted secret, importing+encrypting a dev plaintext file on first use.
    private static func secret() -> Data? {
        if let data = decryptStoredSecret() { return data }
        if let imported = importPlaintextSecret() {
            try? encryptAndStore(imported)
            return imported
        }
        return nil
    }

    private static func symmetricKey() -> SymmetricKey {
        if let existing = keychainRead() { return SymmetricKey(data: existing) }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        keychainWrite(raw)
        return fresh
    }

    private static func encryptAndStore(_ secret: Data) throws {
        let sealed = try AES.GCM.seal(secret, using: symmetricKey())
        guard let combined = sealed.combined else { return }
        try combined.write(to: encFileURL, options: .atomic)
    }

    private static func decryptStoredSecret() -> Data? {
        guard let combined = try? Data(contentsOf: encFileURL),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: symmetricKey()) else { return nil }
        return plain
    }

    /// Dev-only: read secrets/tool_secret (hex/ascii), then it gets encrypted and this
    /// plaintext path is no longer consulted once the .enc exists.
    private static func importPlaintextSecret() -> Data? {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/secrets/tool_secret",
            Bundle.main.bundlePath + "/../secrets/tool_secret",
            Bundle.main.bundlePath + "/../../secrets/tool_secret",
        ]
        for p in candidates {
            if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return Data(t.utf8) }
            }
        }
        return nil
    }

    // MARK: - Keychain

    private static func keychainWrite(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainRead() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
