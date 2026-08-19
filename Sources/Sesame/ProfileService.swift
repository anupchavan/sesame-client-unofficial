import Foundation

/// Account profile from GET/PATCH /user. Shared across all agents (the model reads it as
/// context), surfaced per-agent in the inspector.
struct UserProfile: Equatable {
    var uuid: String = ""
    var email: String = ""
    var displayName: String = ""
    var nickname: String = ""
    var birthday: String = ""        // YYYY-MM-DD
    var gender: String = ""          // MALE | FEMALE | NON_BINARY | OTHER | ""
    var interests: [String] = []     // ≤32 chars each
    var motivations: [String] = []   // enum, see Motivation.all
    var customMotivations: [String] = []
    var allowTrainingFromCalls = true
    var preferProductNewsEmails = true

    static func from(_ json: [String: Any]) -> UserProfile {
        func strings(_ any: Any?) -> [String] { (any as? [String]) ?? [] }
        return UserProfile(
            uuid: json["uuid"] as? String ?? "",
            email: json["email"] as? String ?? "",
            displayName: json["display_name"] as? String ?? "",
            nickname: json["nickname"] as? String ?? "",
            birthday: json["birthday"] as? String ?? "",
            gender: json["gender"] as? String ?? "",
            interests: strings(json["interests"]),
            motivations: strings(json["motivations"]),
            customMotivations: strings(json["custom_motivations"]),
            allowTrainingFromCalls: json["allow_training_from_calls"] as? Bool ?? true,
            preferProductNewsEmails: json["prefer_product_news_emails"] as? Bool ?? true)
    }
}

enum Motivation: String, CaseIterable {
    case quickInsights = "QUICK_INSIGHTS"
    case exploreCuriosity = "EXPLORE_CURIOSITY"
    case soundingBoard = "SOUNDING_BOARD"
    case brainstormingPartner = "BRAINSTORMING_PARTNER"

    var label: String {
        switch self {
        case .quickInsights: "Quick insights"
        case .exploreCuriosity: "Explore curiosity"
        case .soundingBoard: "Sounding board"
        case .brainstormingPartner: "Brainstorming partner"
        }
    }
}

struct CallDetails: Equatable {
    var summary: String = ""
    var detailedSummary: String?
}

enum CallService {
    static func details(callID: Int) async throws -> CallDetails {
        let token = try await AuthManager.shared.validIDToken()
        var req = URLRequest(url: URL(string: "https://app.sesame.com/api/user/calls/\(callID)/details")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("iOS", forHTTPHeaderField: "Client-Name")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "call", code: 0, userInfo: [NSLocalizedDescriptionKey: "Couldn't load call"])
        }
        let activity = (json["activity"] as? [String: Any]) ?? [:]
        return CallDetails(summary: activity["summary"] as? String ?? "",
                           detailedSummary: activity["detailed_summary"] as? String)
    }
}

enum FeedbackService {
    /// Best-effort per-message rating. The server exposes no verified per-message reaction
    /// endpoint (WS react methods all return -32601), so this records to /feedback/general;
    /// the thumb state itself persists locally in the message cache.
    static func send(rating: Int, messageUUID: String?, agent: Agent, text: String) async {
        guard let token = try? await AuthManager.shared.validIDToken() else { return }
        var req = URLRequest(url: URL(string: "https://app.sesame.com/api/feedback/general")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("iOS", forHTTPHeaderField: "Client-Name")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "rating": rating > 0 ? "positive" : "negative",
            "category": "message",
            "character": agent.rawValue,
            "message_uuid": messageUUID ?? "",
            "comment": String(text.prefix(200)),
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}

enum ProfileService {
    static func fetch() async throws -> UserProfile {
        let json = try await request(method: "GET", body: nil)
        return UserProfile.from(json)
    }

    /// PATCH the changed fields; server echoes the full updated profile.
    static func update(_ p: UserProfile) async throws -> UserProfile {
        let body: [String: Any] = [
            "nickname": p.nickname,
            "gender": p.gender,
            "birthday": p.birthday,
            "interests": p.interests,
            "motivations": p.motivations,
            "custom_motivations": p.customMotivations,
            "allow_training_from_calls": p.allowTrainingFromCalls,
            "prefer_product_news_emails": p.preferProductNewsEmails,
        ]
        let json = try await request(method: "PATCH", body: body)
        return UserProfile.from(json)
    }

    private static func request(method: String, body: [String: Any]?) async throws -> [String: Any] {
        let token = try await AuthManager.shared.validIDToken()
        var req = URLRequest(url: URL(string: "https://app.sesame.com/api/user")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("iOS", forHTTPHeaderField: "Client-Name")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "profile", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "profile", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
