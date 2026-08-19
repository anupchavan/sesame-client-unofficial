import SwiftUI

@main
struct SesameApp: App {
    @StateObject private var store = AppStore()

    /// Headless smoke test: SESAME_SELFTEST=1 sends a message to Maya and logs the outcome.
    private func runSelfTestIfRequested() {
        if ProcessInfo.processInfo.environment["SESAME_UPLOADTEST"] == "1" {
            Task { @MainActor in
                let img = NSImage(size: NSSize(width: 8, height: 8))
                img.lockFocus(); NSColor.systemPurple.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8)); img.unlockFocus()
                guard let jpeg = AttachmentService.jpegData(from: img) else { WSLog.log("uploadtest: no jpeg", always: true); NSApp.terminate(nil); return }
                do {
                    let key = try await AttachmentService.upload(data: jpeg, fileName: "file.jpg", mimeType: "image/jpeg")
                    WSLog.log("uploadtest: SUCCESS key=\(key)", always: true)
                } catch {
                    WSLog.log("uploadtest: FAILED \(error)", always: true)
                }
                NSApp.terminate(nil)
            }
            return
        }
        guard ProcessInfo.processInfo.environment["SESAME_SELFTEST"] == "1" else { return }
        Task { @MainActor in
            let vm = store.vm(.maya)
            for _ in 0..<60 where !vm.connection.isConnected {
                try? await Task.sleep(for: .seconds(0.5))
            }
            WSLog.log("selftest: connection=\(vm.connection.label) history=\(vm.messages.count)", always: true)
            vm.draft = "self-test: reply with just the word pong"
            vm.send()
            try? await Task.sleep(for: .seconds(25))
            let last = vm.messages.last
            WSLog.log("selftest: messages=\(vm.messages.count) lastSender=\(last?.sender == .agent ? "agent" : "user") lastText=\(last?.text.prefix(80) ?? "-")", always: true)
            if ProcessInfo.processInfo.environment["SESAME_CALLTEST"] == "1" {
                WSLog.log("calltest: starting call to Maya", always: true)
                store.startCall(with: .maya)
                for _ in 0..<60 {
                    try? await Task.sleep(for: .seconds(0.5))
                    if case .active = store.call.state { break }
                    if case .ended = store.call.state { break }
                }
                WSLog.log("calltest: state=\(store.call.state)", always: true)
                try? await Task.sleep(for: .seconds(6))
                WSLog.log("calltest: final state=\(store.call.state)", always: true)
                store.call.end()
                try? await Task.sleep(for: .seconds(1))
            }
            NSApp.terminate(nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.call)
                .background(WindowCustomizer())
                .frame(minWidth: 880, minHeight: 540)
                .onAppear {
                    store.connectAll()
                    Notifier.shared.requestAuthorizationIfEnabled()
                    LocationProvider.shared.start()
                    runSelfTestIfRequested()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.setAppActive(true)
                    store.refreshOnFocus()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didResignActiveNotification)) { _ in
                    store.setAppActive(false)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { store.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Applies modern macOS window chrome: transparent, taller title bar with padded
/// (vertically centered) traffic lights — the macOS 26/27 look.
struct WindowCustomizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            let toolbar = NSToolbar(identifier: "sesame.empty")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar          // taller unified title bar → padded traffic lights
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
