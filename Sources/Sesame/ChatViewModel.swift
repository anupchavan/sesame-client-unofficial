import SwiftUI

/// State + logic for one agent conversation.
@MainActor
final class ChatViewModel: ObservableObject, Identifiable {
    let agent: Agent
    let client: ChatClient

    @Published var messages: [ChatMessage] = []
    @Published var connection: ConnectionState = .idle
    @Published var isTyping = false
    @Published var activity: String?
    @Published var unread = 0
    @Published var draft = ""
    @Published var pendingImages: [Data] = []   // queued JPEG data
    @Published var isSending = false
    @Published var errorBanner: String?
    @Published var isLoadingOlder = false
    @Published var historyExhausted = false

    private var seenIDs = Set<String>()
    private var typingClearTask: Task<Void, Never>?
    /// True while the user is looking at this conversation (selected + app frontmost).
    var isActiveView = false { didSet { if isActiveView { markReadNow() } } }
    private var didInitialLoad = false
    private var notifyHighwater = Date.distantPast

    nonisolated var id: String { agent.rawValue }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    static func parseDate(_ s: String?) -> Date {
        guard let s else { return Date() }
        return isoFrac.date(from: s) ?? iso.date(from: s) ?? Date()
    }

    private var saveTask: Task<Void, Never>?
    private var lastSyncAt = Date.distantPast

    init(agent: Agent) {
        self.agent = agent
        self.client = ChatClient(agent: agent)
        // Instant launch: show the cached conversation before any network.
        let cached = ChatCache.load(agent)
        messages = cached
        for m in cached {
            seenIDs.insert(m.id)
            if let u = m.serverUUID { seenIDs.insert(u) }
        }
        wire()
    }

    private func wire() {
        client.onState = { [weak self] s in self?.connection = s }
        client.onHistory = { [weak self] raw in self?.ingest(raw, replaceHistory: true) }
        client.onCommittedMessages = { [weak self] raw in self?.ingest(raw, replaceHistory: false) }
        client.onConnected = { [weak self] in Task { await self?.syncRecent() } }
        client.onTyping = { [weak self] in self?.showTyping() }
        client.onActivity = { [weak self] a in self?.activity = a }
        // Unread is computed locally (server push doesn't fan out cross-device); ignore its count.

        client.onStreamStart = { [weak self] mid, _ in
            guard let self else { return }
            self.isTyping = false
            self.activity = nil
            guard !self.messages.contains(where: { $0.id == mid }) else { return }
            self.seenIDs.insert(mid)
            self.messages.append(ChatMessage(id: mid, sender: .agent, text: "", createdAt: Date(), isStreaming: true))
        }
        client.onStreamChunk = { [weak self] mid, token in
            guard let self, let i = self.messages.lastIndex(where: { $0.id == mid }) else { return }
            self.messages[i].text += token
        }
        client.onStreamEnd = { [weak self] mid, final in
            guard let self, let i = self.messages.lastIndex(where: { $0.id == mid }) else { return }
            self.messages[i].isStreaming = false
            defer { self.persist() }
            if let final {
                if let text = final["content"] as? String, !text.isEmpty {
                    self.messages[i].text = text
                }
                if let uuid = final["uuid"] as? String {
                    self.messages[i].serverUUID = uuid
                    self.seenIDs.insert(uuid)
                }
                let atts = Self.parseAttachments(final["attachments"])
                if !atts.isEmpty { self.messages[i].attachments = atts }
            }
        }
    }

    private func showTyping() {
        isTyping = true
        typingClearTask?.cancel()
        typingClearTask = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { isTyping = false }
        }
    }

    // MARK: - Ingest server messages

    static func parseAttachments(_ any: Any?) -> [AttachmentModel] {
        guard let raw = any as? [[String: Any]] else { return [] }
        return raw.map { a in
            AttachmentModel(
                id: (a["uuid"] as? String) ?? (a["storage_key"] as? String) ?? UUID().uuidString,
                mimeType: a["mime_type"] as? String ?? "application/octet-stream",
                fileName: a["file_name"] as? String ?? "file",
                fileSizeBytes: a["file_size_bytes"] as? Int ?? 0,
                storageKey: a["storage_key"] as? String,
                url: (a["url"] as? String).flatMap(URL.init(string:)),
                transcription: a["transcription"] as? String)
        }
    }

    private func ingest(_ raw: [[String: Any]], replaceHistory: Bool) {
        var incoming: [ChatMessage] = []
        for m in raw {
            let type = m["type"] as? Int ?? 0
            let uuid = (m["uuid"] as? String) ?? (m["id"] as? Int).map { String($0) } ?? (m["id"] as? String) ?? UUID().uuidString
            let clientID = m["client_id"] as? String
            let senderRaw = m["sender"] as? String ?? ""
            let content = m["content"] as? String ?? ""
            let date = Self.parseDate(m["created_at"] as? String)

            if let clientID, seenIDs.contains(clientID) {
                // Echo of our own optimistic message: record the server uuid + URLs, but KEEP
                // the local bytes we already have so the image never re-downloads.
                if let i = messages.firstIndex(where: { $0.id == clientID }) {
                    messages[i].serverUUID = uuid
                    var atts = Self.parseAttachments(m["attachments"])
                    if !atts.isEmpty {
                        let existing = messages[i].attachments
                        for j in atts.indices where atts[j].localData == nil {
                            if j < existing.count, let local = existing[j].localData {
                                atts[j].localData = local
                            }
                        }
                        messages[i].attachments = atts
                    }
                }
                seenIDs.insert(uuid)
                continue
            }
            if seenIDs.contains(uuid) { continue }
            seenIDs.insert(uuid)
            if let clientID { seenIDs.insert(clientID) }

            var msg = ChatMessage(
                id: uuid,
                serverUUID: uuid,
                sender: senderRaw == "user" ? .user : .agent,
                text: content,
                attachments: Self.parseAttachments(m["attachments"]),
                createdAt: date)

            if type == 1 {
                let callID = (m["call_id"] as? Int) ?? (m["call_id"] as? NSNumber)?.intValue
                msg.kind = .call(Self.parseCallSummary(content, callID: callID, started: date))
                msg.text = ""
            } else if type != 0 && content.isEmpty && msg.attachments.isEmpty {
                continue
            }
            incoming.append(msg)
        }
        guard !incoming.isEmpty else { return }
        messages.append(contentsOf: incoming)
        messages.sort { $0.createdAt < $1.createdAt }
        persist()
        handleUnreadAndNotify(incoming)
    }

    /// New agent messages that arrived after the first load: badge + notify when the user
    /// isn't currently looking at this conversation. The initial load is silent.
    private func handleUnreadAndNotify(_ incoming: [ChatMessage]) {
        defer {
            if let newest = messages.last?.createdAt { notifyHighwater = max(notifyHighwater, newest) }
        }
        guard didInitialLoad else { didInitialLoad = true; return }
        let fresh = incoming.filter { $0.sender == .agent && $0.createdAt > notifyHighwater
            && ($0.kind == .text ? !$0.text.isEmpty : true) }
        guard !fresh.isEmpty else { return }
        if isActiveView {
            markReadNow() // caught up live
        } else {
            unread += fresh.count
            for m in fresh {
                let preview: String
                if case .call(let c) = m.kind { preview = c.title }
                else { preview = m.text.isEmpty ? "Sent an attachment" : m.text }
                Notifier.shared.post(agent: agent, body: preview)
            }
        }
    }

    private func markReadNow() {
        unread = 0
        client.markRead()
    }

    // MARK: - Sync & cache

    /// Delta pull: grab the most recent page; dedupe drops everything already known, so this
    /// is cheap and never re-downloads the whole history. Runs on connect and on focus.
    func syncRecent(force: Bool = false) async {
        guard connection.isConnected else { return }
        // Coalesce bursts of focus events.
        if !force, Date().timeIntervalSince(lastSyncAt) < 2 { return }
        lastSyncAt = Date()
        let limit = messages.isEmpty ? 100 : 30
        await client.fetchHistory(before: nil, limit: limit)
    }

    func setFeedback(_ messageID: String, _ value: Int) {
        guard let i = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let newValue = messages[i].feedback == value ? 0 : value // tap again to clear
        messages[i].feedback = newValue
        persist()
        if newValue != 0 {
            let m = messages[i]
            Task { await FeedbackService.send(rating: newValue, messageUUID: m.serverUUID ?? m.id,
                                              agent: agent, text: m.text) }
        }
    }

    private func persist() {
        saveTask?.cancel()
        let snapshot = messages
        let agent = agent
        saveTask = Task.detached(priority: .utility) {
            ChatCache.save(agent, snapshot)
        }
    }

    private static func parseCallSummary(_ content: String, callID: Int?, started: Date) -> CallSummary {
        var title = "Voice call", subtitle = "", durationMs = 0
        if let d = content.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            durationMs = (obj["duration_ms"] as? Int) ?? 0
            let raw = (obj["summary"] as? String) ?? (obj["title"] as? String) ?? ""
            let lines = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if let first = lines.first, !first.isEmpty { title = String(first) }
            if lines.count > 1 { subtitle = lines[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return CallSummary(callID: callID, title: title, subtitle: subtitle,
                           durationMs: durationMs, startedAt: started)
    }

    /// Load the page of messages older than the current oldest (scroll-to-top pagination).
    func loadOlder() async {
        guard !isLoadingOlder, !historyExhausted, let oldest = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        let before = messages.count
        let raw = await client.fetchHistory(before: oldest.createdAt)
        // Nothing returned, or everything was already known → we've reached the beginning.
        if raw == 0 || messages.count == before { historyExhausted = true }
    }

    // MARK: - Sending

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty else { return }
        draft = ""
        pendingImages = []
        Task { await sendMessage(text: text, images: images) }
    }

    private func sendMessage(text: String, images: [Data]) async {
        isSending = !images.isEmpty
        defer { isSending = false }
        let clientID = UUID().uuidString.lowercased()

        var optimisticAtts: [AttachmentModel] = []
        var wireAtts: [[String: Any]] = []
        do {
            for data in images {
                let key = try await AttachmentService.upload(data: data, fileName: "file.jpg", mimeType: "image/jpeg")
                wireAtts.append(["mime_type": "image/jpeg", "file_name": "image.jpg",
                                 "file_size_bytes": data.count, "storage_key": key])
                optimisticAtts.append(AttachmentModel(id: key, mimeType: "image/jpeg", fileName: "image.jpg",
                                                      fileSizeBytes: data.count, storageKey: key, localData: data))
            }
        } catch {
            errorBanner = "Image upload failed — message not sent"
            return
        }

        appendOptimistic(clientID: clientID, text: text, attachments: optimisticAtts)
        ensureConnected()
        client.sendChatMessage(text: text, clientID: clientID, attachments: wireAtts)
    }

    func sendVoiceNote(fileURL: URL) async {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        isSending = true
        defer { isSending = false }
        let ts = Int(Date().timeIntervalSince1970)
        let fileName = "voice-\(ts).m4a"
        do {
            let key = try await AttachmentService.upload(data: data, fileName: "file.m4a", mimeType: "audio/mp4")
            let clientID = UUID().uuidString.lowercased()
            let att = AttachmentModel(id: key, mimeType: "audio/mp4", fileName: fileName,
                                      fileSizeBytes: data.count, storageKey: key, localData: data)
            appendOptimistic(clientID: clientID, text: "", attachments: [att])
            ensureConnected()
            client.sendChatMessage(text: "", clientID: clientID, attachments: [[
                "mime_type": "audio/mp4", "file_name": fileName,
                "file_size_bytes": data.count, "storage_key": key,
            ]])
        } catch {
            errorBanner = "Voice note upload failed"
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func appendOptimistic(clientID: String, text: String, attachments: [AttachmentModel]) {
        seenIDs.insert(clientID)
        messages.append(ChatMessage(id: clientID, sender: .user, text: text,
                                    attachments: attachments, createdAt: Date()))
        persist()
    }

    private func ensureConnected() {
        if !connection.isConnected { client.connect() }
    }

    var lastPreview: String {
        guard let m = messages.last(where: { $0.kind == .text || $0.sender == .agent }) else { return "" }
        if case .call(let c) = m.kind { return c.title }
        if !m.text.isEmpty { return m.text }
        if let a = m.attachments.first {
            return a.isImage ? "Photo" : a.isAudio ? "Voice note" : a.fileName
        }
        return ""
    }
}

/// App-wide store: the four conversations + selection.
@MainActor
final class AppStore: ObservableObject {
    @Published var selected: Agent = .maya {
        didSet { updateActiveView() }
    }
    @Published var showSettings = false
    @Published var showInspector = false
    @Published var showSidebar = true
    @Published var selectedCall: CallSummary?
    let chats: [Agent: ChatViewModel]
    let call = CallManager()
    @Published var callAgent: Agent?
    private var appActive = true

    init() {
        var dict: [Agent: ChatViewModel] = [:]
        for a in Agent.allCases { dict[a] = ChatViewModel(agent: a) }
        chats = dict
        updateActiveView()
    }

    private var foregroundRefresh: Task<Void, Never>?
    private var backgroundPoll: Task<Void, Never>?

    func vm(_ agent: Agent) -> ChatViewModel { chats[agent]! }

    /// Exactly one conversation is "active" (its messages arrive silently): the selected one,
    /// and only while the app is frontmost.
    private func updateActiveView() {
        for a in Agent.allCases {
            chats[a]!.isActiveView = (a == selected && appActive)
        }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        updateActiveView()
        if active { startForegroundRefresh() } else { stopForegroundRefresh() }
        // Background poll runs only while unfocused, to catch messages for notifications.
        active ? stopBackgroundPoll() : startBackgroundPoll()
    }

    private func startBackgroundPoll() {
        backgroundPoll?.cancel()
        guard AuthManager.shared.hasCredentials, Notifier.shared.enabled else { return }
        backgroundPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                for a in Agent.allCases {
                    let vm = self.chats[a]!
                    if vm.connection.isConnected { await vm.syncRecent(force: true) }
                }
            }
        }
    }

    private func stopBackgroundPoll() {
        backgroundPoll?.cancel()
        backgroundPoll = nil
    }

    /// While the app is frontmost, delta-sync the visible conversation on a slow cadence —
    /// the only path the server leaves for catching a message typed on another device while
    /// you're already looking at the Mac (there is no socket fan-out, and focus won't re-fire).
    func startForegroundRefresh() {
        foregroundRefresh?.cancel()
        guard AuthManager.shared.hasCredentials else { return }
        foregroundRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard let self else { return }
                await self.vm(self.selected).syncRecent()
            }
        }
    }

    func stopForegroundRefresh() {
        foregroundRefresh?.cancel()
        foregroundRefresh = nil
    }

    func connectAll() {
        guard AuthManager.shared.hasCredentials else { return }
        for a in Agent.allCases { chats[a]!.client.connect() }
    }

    /// Called when the window regains focus: delta-sync every conversation so anything sent
    /// from another device (mobile) shows up. Event-driven — no background polling.
    func refreshOnFocus() {
        guard AuthManager.shared.hasCredentials else { return }
        for a in Agent.allCases {
            let vm = chats[a]!
            if vm.connection.isConnected {
                Task { await vm.syncRecent() }
            } else {
                vm.client.connect() // reconnect drops → onConnected triggers its own sync
            }
        }
    }

    func startCall(with agent: Agent) {
        guard !call.isActive else { return }
        callAgent = agent
        let vm = vm(agent)
        Task {
            if !vm.connection.isConnected {
                vm.client.connect()
                for _ in 0..<40 where !vm.connection.isConnected {
                    try? await Task.sleep(for: .seconds(0.25))
                }
            }
            await call.start(agent: agent, client: vm.client)
        }
    }
}
