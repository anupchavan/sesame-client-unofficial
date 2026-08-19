import SwiftUI
import AVFoundation

struct MessageBubble: View {
    let message: ChatMessage
    let agent: Agent
    var onOpenCall: (CallSummary) -> Void = { _ in }
    var onFeedback: (String, Int) -> Void = { _, _ in }

    private var isUser: Bool { message.sender == .user }

    var body: some View {
        switch message.kind {
        case .call(let summary):
            CallSummaryRow(summary: summary) { onOpenCall(summary) }
                .padding(.vertical, 8)
        case .text:
            HStack(alignment: .bottom, spacing: 0) {
                if isUser { Spacer(minLength: 60) }
                VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                    ForEach(message.attachments) { att in
                        AttachmentView(attachment: att, isUser: isUser, accent: agent.accent)
                    }
                    if !message.text.isEmpty || message.isStreaming {
                        textBubble
                    }
                    if !isUser && !message.isStreaming && !message.text.isEmpty {
                        FeedbackRow(message: message, onFeedback: onFeedback)
                    }
                }
                .frame(maxWidth: isUser ? 480 : .infinity, alignment: isUser ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
        }
    }

    @ViewBuilder
    private var textBubble: some View {
        if isUser {
            Text(message.text)
                .font(.system(size: 13.5))
                .lineSpacing(6)   // ≈ 1.5 line height
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ax1))
        } else if message.text.isEmpty && message.isStreaming {
            Text("…").font(.system(size: 13.5)).foregroundStyle(Theme.tx2)
        } else {
            MarkdownText(text: message.text)  // agent text sits directly on the canvas, markdown-rendered
                .padding(.vertical, 1)
        }
    }
}

/// Thumbs up / down (persisted locally, best-effort synced) + copy, under agent messages.
struct FeedbackRow: View {
    let message: ChatMessage
    let onFeedback: (String, Int) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            iconButton(message.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup",
                       active: message.feedback == 1) { onFeedback(message.id, 1) }
            iconButton(message.feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                       active: message.feedback == -1) { onFeedback(message.id, -1) }
            iconButton(copied ? "checkmark" : "square.on.square", active: copied) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            }
        }
        .padding(.top, 6)
        .padding(.leading, 2)
    }

    private func iconButton(_ name: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(active ? Theme.tx2 : Theme.tx3)   // muted grey, slightly darker when active
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain).focusEffectDisabled()
    }
}

/// Centered call summary: "Call ended (Ns)" above a tappable title with chevron.
struct CallSummaryRow: View {
    let summary: CallSummary
    let open: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 10))
                Text("Call ended (\(summary.durationLabel))")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Theme.tx3)

            Button(action: open) {
                HStack(spacing: 3) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.tx2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .disabled(summary.callID == nil)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CallDetailsSheet: View {
    let summary: CallSummary
    @Environment(\.dismiss) private var dismiss
    @State private var details: CallDetails?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Call Details")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.tx1)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.tx3)
                }
                .buttonStyle(.plain).focusEffectDisabled()
            }
            .padding(.bottom, 18)

            Text(summary.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.tx1)
            Text("\(Self.dateLabel(summary.startedAt)) · \(summary.durationLabel)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tx3)
                .padding(.top, 3)

            Group {
                if loading {
                    HStack { ProgressView().controlSize(.small); Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.tx3) }
                        .padding(.top, 16)
                } else {
                    let body = bodyText
                    if body.isEmpty {
                        Text("No summary available.")
                            .font(.system(size: 13)).foregroundStyle(Theme.tx3).padding(.top, 16)
                    } else {
                        Text(body)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.tx1)
                            .textSelection(.enabled)
                            .padding(.top, 16)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 380, height: 320, alignment: .topLeading)
        .background(Theme.bg1)
        .task {
            if let id = summary.callID {
                details = try? await CallService.details(callID: id)
            }
            loading = false
        }
    }

    /// Prefer the server's fuller summary; fall back to the subtitle carried inline.
    private var bodyText: String {
        if let d = details {
            if let ds = d.detailedSummary, !ds.isEmpty { return ds }
            // Drop the title line (already shown above) from the summary.
            let rest = d.summary.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if rest.count > 1 { return rest[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return summary.subtitle
    }

    static func dateLabel(_ d: Date) -> String {
        let time = d.formatted(date: .omitted, time: .shortened) // system locale + 12/24h
        if Calendar.current.isDateInToday(d) { return "Today \(time)" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday \(time)" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

struct AttachmentView: View {
    let attachment: AttachmentModel
    let isUser: Bool
    let accent: Color

    var body: some View {
        if attachment.isImage {
            ImageAttachmentView(attachment: attachment)
        } else if attachment.isAudio {
            VoiceNoteView(attachment: attachment, isUser: isUser, accent: accent)
        } else {
            Label(attachment.fileName, systemImage: "doc")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.tx2)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg2))
        }
    }
}

struct ImageAttachmentView: View {
    let attachment: AttachmentModel
    @StateObject private var loader = AttachmentImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(nsImage: img).resizable().scaledToFill()
            } else if loader.failed {
                placeholder(icon: "photo.badge.exclamationmark")
            } else {
                placeholder(icon: nil)
            }
        }
        .frame(maxWidth: 300, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ui1, lineWidth: 1))
        .onAppear { loader.load(attachment) }
        .onChange(of: attachment.url) { loader.load(attachment) }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            Rectangle().fill(Theme.bg2)
            if let icon {
                Image(systemName: icon).foregroundStyle(Theme.tx3).font(.system(size: 20))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 220, height: 160)
    }
}

/// Voice note bubble: play/pause, progress, optional transcription.
struct VoiceNoteView: View {
    let attachment: AttachmentModel
    let isUser: Bool
    let accent: Color
    @StateObject private var player = VoicePlayer()
    @State private var showTranscript = false

    private let rowWidth: CGFloat = 224

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isUser ? Theme.ax1 : .white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(accent)))
                }
                .buttonStyle(.plain).focusEffectDisabled()

                ZStack(alignment: .leading) {
                    Capsule().fill((isUser ? Color.white : Theme.tx3).opacity(0.35))
                    Capsule().fill(isUser ? Color.white : accent)
                        .frame(width: max(4, 108 * player.progress))
                }
                .frame(width: 108, height: 4)

                Text(player.timeLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isUser ? .white.opacity(0.85) : Theme.tx2)

                Spacer(minLength: 0)

                if attachment.transcription?.isEmpty == false {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showTranscript.toggle() }
                    } label: {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11))
                            .foregroundStyle(isUser ? .white.opacity(0.8) : Theme.tx2)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain).focusEffectDisabled()
                    .help("Show transcription")
                }
            }
            .frame(width: rowWidth)

            if showTranscript, let t = attachment.transcription {
                Text(t)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(isUser ? .white.opacity(0.9) : Theme.tx2)
                    .frame(width: rowWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isUser ? AnyShapeStyle(Theme.ax1) : AnyShapeStyle(Theme.bg2))
        )
        .onDisappear { player.stop() }
    }

    private func toggle() {
        if player.isPlaying { player.pause(); return }
        if let data = attachment.localData {
            player.play(data: data)
        } else if let url = attachment.url {
            player.play(url: url)
        }
    }
}

@MainActor
final class VoicePlayer: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var timeLabel = "0:00"

    private var player: AVPlayer?
    private var timeObserver: Any?

    func play(url: URL) {
        if player == nil {
            let p = AVPlayer(url: url)
            attach(p)
        }
        player?.play()
        isPlaying = true
    }

    func play(data: Data) {
        if player == nil {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("vp-\(abs(data.hashValue)).m4a")
            if !FileManager.default.fileExists(atPath: tmp.path) {
                try? data.write(to: tmp)
            }
            attach(AVPlayer(url: tmp))
        }
        player?.play()
        isPlaying = true
    }

    private func attach(_ p: AVPlayer) {
        player = p
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 10),
                                                 queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, let item = self.player?.currentItem else { return }
                let dur = item.duration.seconds
                let cur = time.seconds
                if dur.isFinite, dur > 0 {
                    self.progress = cur / dur
                    let remaining = Int(max(0, dur - cur).rounded())
                    self.timeLabel = String(format: "%d:%02d", remaining / 60, remaining % 60)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 0
                self?.player?.seek(to: .zero)
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        pause()
        if let o = timeObserver { player?.removeTimeObserver(o) }
        timeObserver = nil
        player = nil
    }
}
