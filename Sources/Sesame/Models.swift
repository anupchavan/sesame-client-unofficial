import SwiftUI

enum Agent: String, CaseIterable, Identifiable, Hashable {
    case maya = "Maya"
    case miles = "Miles"
    case charlie = "Charlie"
    case simone = "Simone"

    var id: String { rawValue }
    var name: String { rawValue }

    /// Single neutral app accent (per-agent colors removed by request).
    var accent: Color { Theme.ax1 }
}

struct AttachmentModel: Identifiable, Equatable {
    let id: String
    var mimeType: String
    var fileName: String
    var fileSizeBytes: Int
    var storageKey: String?
    var url: URL?
    var transcription: String?
    var localData: Data?          // optimistic display before the server echoes a URL

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isAudio: Bool { mimeType.hasPrefix("audio/") }
}

struct CallSummary: Identifiable, Equatable {
    var callID: Int?
    var title: String       // first line of the summary
    var subtitle: String    // remaining lines
    var durationMs: Int
    var startedAt: Date

    var id: String { callID.map(String.init) ?? title + "\(durationMs)" }

    var durationLabel: String {
        let s = max(0, durationMs / 1000)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: Equatable { case text, call(CallSummary) }
    enum Sender: Equatable { case user, agent }

    let id: String                // client_id for ours, uuid for theirs
    var serverUUID: String?
    var sender: Sender
    var text: String
    var attachments: [AttachmentModel] = []
    var createdAt: Date
    var kind: Kind = .text
    var isStreaming = false
    var failed = false
    var feedback: Int = 0   // 0 none, 1 thumbs-up, -1 thumbs-down
}

enum ConnectionState: Equatable {
    case idle, connecting, connected
    case reconnecting(attempt: Int)
    case failed(String)

    var label: String {
        switch self {
        case .idle: "offline"
        case .connecting: "connecting…"
        case .connected: "online"
        case .reconnecting: "reconnecting…"
        case .failed(let e): e
        }
    }
    var isConnected: Bool { self == .connected }
}

enum CallState: Equatable {
    case none
    case connecting
    case ringing
    case active(since: Date)
    case ended(String?)
}
