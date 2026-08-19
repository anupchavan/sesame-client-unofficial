import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var call: CallManager
    @State private var didInitialScroll = false

    var body: some View {
        ZStack(alignment: .top) {
            messagesList
            if let banner = vm.errorBanner {
                ErrorBanner(text: banner) { vm.errorBanner = nil }
            }
            if call.isActive, store.callAgent == vm.agent {
                CallCard(agent: vm.agent)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }        // floating top bar
        .safeAreaInset(edge: .bottom, spacing: 0) { ComposerView(vm: vm) } // floating input pill
        .background(Theme.bg2) // main canvas = the grey Maya's bubbles used to be
        .animation(.spring(duration: 0.3), value: call.isActive)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .overlay {
            if !AuthManager.shared.hasCredentials && vm.messages.isEmpty {
                NoCredentialsView()
            }
        }
        .sheet(item: $store.selectedCall) { CallDetailsSheet(summary: $0) }
    }

    /// Agents are always "online" — only surface transient states (activity, connecting, errors).
    private var headerSubtitle: String? {
        if let a = vm.activity { return a }
        switch vm.connection {
        case .connected, .idle: return nil
        case .connecting: return "connecting…"
        case .reconnecting: return "reconnecting…"
        case .failed(let e): return e
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !store.showSidebar {
                Button {
                    withAnimation(.spring(duration: 0.34)) { store.showSidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.tx2)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusEffectDisabled()
                .help("Show sidebar")
                .padding(.leading, 72) // clear traffic lights when collapsed
            }

            Button {
                withAnimation(.spring(duration: 0.32)) { store.showInspector.toggle() }
            } label: {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.agent.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.tx1)
                        if let sub = headerSubtitle {
                            Text(sub)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tx2)     // muted grey, not yellow
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: headerSubtitle)
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.tx3)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help("Edit profile")

            CallButton(active: call.isActive) { store.startCall(with: vm.agent) }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background {
            Rectangle()
                .fill(.regularMaterial)          // stronger blur
                .shadow(color: .black.opacity(0.05), radius: 10, y: 2)  // softer shadow
        }
    }

    private struct Row: Identifiable {
        let index: Int
        let id: String
        let showDivider: Bool   // >15 min gap → timestamp divider
        let topPadding: CGFloat // tight inside a same-sender group, roomy between groups
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !vm.messages.isEmpty && !vm.historyExhausted {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small).opacity(vm.isLoadingOlder ? 1 : 0)
                            Spacer()
                        }
                        .frame(height: 30)
                        .onAppear {
                            // Don't paginate while the view is still settling at the bottom on open.
                            guard didInitialScroll else { return }
                            let anchor = vm.messages.first?.id
                            Task {
                                await vm.loadOlder()
                                if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                            }
                        }
                    }
                    ForEach(rows()) { row in
                        let msg = vm.messages[row.index]
                        if row.showDivider {
                            TimestampDivider(date: msg.createdAt)
                        }
                        MessageBubble(message: msg, agent: vm.agent,
                                      onOpenCall: { store.selectedCall = $0 },
                                      onFeedback: { vm.setFeedback($0, $1) })
                            .padding(.leading, msg.sender == .agent ? -18 : 0)  // agent flush to both edges
                            .padding(.trailing, -18)                            // bubbles flush to the right edge
                            .padding(.top, row.showDivider ? 0 : row.topPadding)
                            .id(msg.id)
                    }
                    if vm.isTyping {
                        TypingIndicator(agent: vm.agent)
                            .padding(.leading, -18)   // flush left, like agent messages
                            .padding(.top, 40)
                    }
                    Color.clear.frame(height: 40).id("bottom")   // gap before the input bar, matching message spacing
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .frame(maxWidth: 700)                     // clamp the conversation column…
                .frame(maxWidth: .infinity)               // …and center it, responsively
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                scrollToBottom(proxy, animated: false)
                // Allow pagination only once the initial bottom-scroll has settled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { didInitialScroll = true }
            }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy, animated: true) }        // new message (sent or received)
            .onChange(of: vm.messages.last?.text) { scrollToBottom(proxy, animated: false) }  // streaming reply grows
            .onChange(of: vm.isTyping) { if vm.isTyping { scrollToBottom(proxy, animated: true) } }
        }
    }

    /// Scroll after the current layout pass so new content is measured first — scrolling
    /// synchronously inside onChange lands on the stale (pre-insert) bottom.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func rows() -> [Row] {
        var result: [Row] = []
        var prev: ChatMessage?
        for (i, m) in vm.messages.enumerated() {
            let divider = prev.map { m.createdAt.timeIntervalSince($0.createdAt) > 900 } ?? true
            let grouped = prev.map {
                $0.sender == m.sender && $0.kind == .text && m.kind == .text
                    && m.createdAt.timeIntervalSince($0.createdAt) < 180
            } ?? false
            // Tight within the same sender's run; 40px gap when the sender changes.
            result.append(Row(index: i, id: m.id, showDivider: divider, topPadding: grouped ? 3 : 40))
            prev = m
        }
        return result
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url),
                      let jpeg = AttachmentService.jpegData(from: image) else { return }
                Task { @MainActor in vm.pendingImages.append(jpeg) }
            }
        }
        return handled
    }
}

/// Call button with SF Symbol animation: bounces on press, pulses while a call is active.
struct CallButton: View {
    let active: Bool
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? .white : Theme.ax1)
                .frame(width: 32, height: 32)
                .background(Circle().fill(active ? AnyShapeStyle(Theme.green) : AnyShapeStyle(Theme.bg3)))
                .symbolEffect(.bounce, value: bounce)
                .modifier(PulseIfActive(active: active))
        }
        .buttonStyle(.plain).focusEffectDisabled()
        .disabled(active)
        .help(active ? "In call" : "Voice call")
    }
}

private struct PulseIfActive: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}

struct TimestampDivider: View {
    let date: Date
    var body: some View {
        HStack {
            Spacer()
            Text(Self.format(date))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.tx3)
            Spacer()
        }
        .padding(.vertical, 10)
    }
    static func format(_ d: Date) -> String {
        let time = d.formatted(date: .omitted, time: .shortened) // system locale + 12/24h
        if Calendar.current.isDateInToday(d) { return time }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday \(time)" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

struct TypingIndicator: View {
    let agent: Agent
    @State private var phase = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.tx3)
                    .frame(width: 6, height: 6)
                    .opacity(phase ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.vertical, 6)   // no horizontal padding / bubble — dots sit flush like agent text
        .onAppear { phase = true }
    }
}

struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.yellow)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.tx1)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tx2)
            }.buttonStyle(.plain).focusEffectDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Theme.bg2).shadow(color: .black.opacity(0.15), radius: 8, y: 2))
        .padding(.top, 8)
        .task {
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
    }
}

struct NoCredentialsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(Theme.tx3)
            Text("Add your refresh token to start chatting")
                .font(.system(size: 13))
                .foregroundStyle(Theme.tx2)
            Button("Open Settings") { store.showSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ax1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg1)
    }
}
