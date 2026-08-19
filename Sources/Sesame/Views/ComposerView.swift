import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @ObservedObject var vm: ChatViewModel
    @StateObject private var recorder = AudioRecorder()
    @FocusState private var focused: Bool

    var body: some View {
        // Floating rounded pill, clamped to the content column width and centered.
        VStack(spacing: 8) {
            if !vm.pendingImages.isEmpty {
                pendingImagesRow
            }
            HStack(alignment: .bottom, spacing: 2) {
                if recorder.isRecording {
                    recordingBar
                } else {
                    attachButton
                    inputField
                    if vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && vm.pendingImages.isEmpty {
                        micButton
                    } else {
                        sendButton
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.bg1)
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.ui1, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 14, y: 3)
        )
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Pieces

    @State private var inputHeight: CGFloat = 32
    private var inputField: some View {
        ZStack(alignment: .topLeading) {
            if vm.draft.isEmpty {
                Text("Message \(vm.agent.name)…")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.tx3)
                    .padding(.leading, 2)
                    .padding(.top, 8)   // matches the text view's inset
                    .allowsHitTesting(false)
            }
            GrowingTextView(text: $vm.draft, height: $inputHeight, maxHeight: 140) { vm.send() }
                .frame(height: inputHeight)
        }
    }

    @State private var attachHover = false
    private var attachButton: some View {
        Button(action: pickImages) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.tx2)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.bg2).opacity(attachHover ? 1 : 0))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) { attachHover = hovering }
        }
        .help("Attach image")
    }

    @State private var micBounce = 0
    private var micButton: some View {
        Button {
            micBounce += 1
            Task {
                if await recorder.start() == false {
                    vm.errorBanner = "Microphone unavailable — check System Settings › Privacy"
                }
            }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.tx2)
                .frame(width: 32, height: 32)
                .symbolEffect(.bounce, value: micBounce)
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .help("Record voice note")
    }

    private var sendButton: some View {
        Button(action: { vm.send() }) {
            Group {
                if vm.isSending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .background(Circle().fill(Theme.ax1))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .disabled(vm.isSending)
        .keyboardShortcut(.return, modifiers: [])
    }

    private var recordingBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.red).frame(width: 8, height: 8)
                .opacity(0.5 + 0.5 * Double(recorder.level))
            Text(String(format: "%d:%02d", Int(recorder.duration) / 60, Int(recorder.duration) % 60))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.tx1)
            Capsule()
                .fill(Theme.red.opacity(0.4 + 0.6 * Double(recorder.level)))
                .frame(width: 120 * CGFloat(max(0.08, recorder.level)), height: 4)
                .animation(.linear(duration: 0.1), value: recorder.level)
            Spacer()
            Button {
                _ = recorder.stop(cancelled: true)
            } label: {
                Text("Cancel").font(.system(size: 12.5)).foregroundStyle(Theme.tx2)
            }
            .buttonStyle(.plain).focusEffectDisabled()
            Button {
                if let rec = recorder.stop() {
                    Task { await vm.sendVoiceNote(fileURL: rec.url) }
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.red))
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help("Send voice note")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var pendingImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(vm.pendingImages.enumerated()), id: \.offset) { i, data in
                    if let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    vm.pendingImages.remove(at: i)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain).focusEffectDisabled()
                                .padding(2)
                            }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.begin { resp in
            guard resp == .OK else { return }
            for url in panel.urls {
                if let image = NSImage(contentsOf: url),
                   let jpeg = AttachmentService.jpegData(from: image) {
                    Task { @MainActor in vm.pendingImages.append(jpeg) }
                }
            }
        }
    }
}
