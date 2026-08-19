import Foundation

/// On-disk cache of each conversation so launches are instant and never re-pull the full
/// history. Stores a lightweight snapshot (no image/audio blobs — those reload from their
/// presigned URLs on demand).
enum ChatCache {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sesame/chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func url(_ agent: Agent) -> URL {
        dir.appendingPathComponent("\(agent.rawValue).json")
    }

    static func load(_ agent: Agent) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: url(agent)),
              let dtos = try? JSONDecoder().decode([CachedMessage].self, from: data) else { return [] }
        return dtos.map { $0.toModel() }
    }

    static func save(_ agent: Agent, _ messages: [ChatMessage]) {
        // Cap the on-disk history so the file stays small.
        let trimmed = messages.suffix(400)
        let dtos = trimmed.map(CachedMessage.init(from:))
        guard let data = try? JSONEncoder().encode(dtos) else { return }
        try? data.write(to: url(agent), options: .atomic)
    }
}

private struct CachedAttachment: Codable {
    var id: String
    var mimeType: String
    var fileName: String
    var fileSizeBytes: Int
    var storageKey: String?
    var url: String?
    var transcription: String?

    init(from a: AttachmentModel) {
        id = a.id; mimeType = a.mimeType; fileName = a.fileName; fileSizeBytes = a.fileSizeBytes
        storageKey = a.storageKey; url = a.url?.absoluteString; transcription = a.transcription
    }
    func toModel() -> AttachmentModel {
        AttachmentModel(id: id, mimeType: mimeType, fileName: fileName, fileSizeBytes: fileSizeBytes,
                        storageKey: storageKey, url: url.flatMap(URL.init(string:)),
                        transcription: transcription, localData: nil)
    }
}

private struct CachedMessage: Codable {
    var id: String
    var serverUUID: String?
    var senderIsUser: Bool
    var text: String
    var attachments: [CachedAttachment]
    var createdAt: Date
    var feedback: Int?
    // call summary (nil for plain text)
    var callID: Int?
    var callTitle: String?
    var callSubtitle: String?
    var callDurationMs: Int?

    init(from m: ChatMessage) {
        id = m.id; serverUUID = m.serverUUID; senderIsUser = m.sender == .user
        text = m.text; createdAt = m.createdAt; feedback = m.feedback
        attachments = m.attachments.map(CachedAttachment.init(from:))
        if case .call(let c) = m.kind {
            callID = c.callID; callTitle = c.title; callSubtitle = c.subtitle; callDurationMs = c.durationMs
        }
    }

    func toModel() -> ChatMessage {
        var msg = ChatMessage(id: id, serverUUID: serverUUID, sender: senderIsUser ? .user : .agent,
                              text: text, attachments: attachments.map { $0.toModel() }, createdAt: createdAt)
        msg.feedback = feedback ?? 0
        if let title = callTitle {
            msg.kind = .call(CallSummary(callID: callID, title: title, subtitle: callSubtitle ?? "",
                                         durationMs: callDurationMs ?? 0, startedAt: createdAt))
            msg.text = ""
        }
        return msg
    }
}
