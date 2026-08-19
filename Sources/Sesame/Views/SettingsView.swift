import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sesameApiKey") private var apiKey = ""
    @AppStorage("sesameRefreshToken") private var refreshToken = ""
    @AppStorage("sesameNotifications") private var notifications = true
    @State private var profileEmail: String?
    @State private var confirmClear = false
    @State private var status: String?
    @State private var showHelp = false
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.tx1)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.tx3)
                }
                .buttonStyle(.plain).focusEffectDisabled()
            }

            Picker("", selection: $tab) {
                Text("General").tag(0)
                Text("Advanced").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 { generalTab } else { AdvancedToolSettings() }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.bg1)
        .task { await loadProfile() }
        .confirmationDialog("Clear all chat history on the server?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { Task { await clearHistory() } }
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Firebase API key")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.tx2)
                TextField("AIza…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Refresh token")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.tx2)
                SecureField("AMf-…", text: $refreshToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showHelp.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showHelp ? 90 : 0))
                        Label("How do I find these?", systemImage: "questionmark.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.ax1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusEffectDisabled()

                if showHelp {
                    VStack(alignment: .leading, spacing: 10) {
                        helpStep(1, "Sign in at **app.sesame.com** in your browser.")
                        helpStep(2, "Open DevTools (⌥⌘I) → **Application** tab → **IndexedDB** → `firebaseLocalStorageDb` → `firebaseLocalStorage`.")
                        helpStep(3, "Expand the stored row: **value → stsTokenManager → refreshToken**. Copy the long `AMf-…` string — that's your refresh token.")
                        helpStep(4, "For the API key: DevTools → **Network** tab, filter for `securetoken` or `getAccountInfo`, and copy the `key=` query parameter (`AIza…`) from any request URL.")
                        Text("Both are tied to your own Sesame account and stay on this Mac.")
                            .font(.system(size: 11)).foregroundStyle(Theme.tx3)
                    }
                    .padding(.top, 10)
                    .padding(.leading, 2)
                }
            }

            Toggle(isOn: $notifications) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Notifications").font(.system(size: 12.5)).foregroundStyle(Theme.tx1)
                    Text("Alert me to new messages when the app isn't focused")
                        .font(.system(size: 11)).foregroundStyle(Theme.tx3)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.ax1)
            .onChange(of: notifications) {
                if notifications { Notifier.shared.requestAuthorizationIfEnabled() }
            }

            HStack(spacing: 10) {
                Button("Reconnect") {
                    AuthManager.shared.invalidate()
                    for agent in Agent.allCases {
                        store.vm(agent).client.disconnect()
                        store.vm(agent).client.connect()
                    }
                    status = "Reconnecting…"
                    Task { await loadProfile() }
                }
                Button("Clear chat history", role: .destructive) { confirmClear = true }
                Spacer()
            }
            .controlSize(.small)

            if let status {
                Text(status)
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tx2)
                    .lineLimit(4)
            }
            if let email = profileEmail {
                Label(email, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.green)
            }
        }
    }

    private func helpStep(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.ax1))
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func loadProfile() async {
        guard AuthManager.shared.hasCredentials else {
            status = "Enter your API key and refresh token, then hit Reconnect."
            return
        }
        do {
            let token = try await AuthManager.shared.validIDToken()
            var req = URLRequest(url: URL(string: "https://app.sesame.com/api/user")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("iOS", forHTTPHeaderField: "Client-Name")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                profileEmail = (json["email"] as? String) ?? (json["display_name"] as? String)
                status = nil
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func clearHistory() async {
        do {
            let token = try await AuthManager.shared.validIDToken()
            var req = URLRequest(url: URL(string: "https://app.sesame.com/api/user/clear-chat-history")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("iOS", forHTTPHeaderField: "Client-Name")
            _ = try await URLSession.shared.data(for: req)
            for agent in Agent.allCases {
                store.vm(agent).messages.removeAll()
            }
            status = "History cleared"
        } catch {
            status = "Clear failed: \(error.localizedDescription)"
        }
    }
}

/// Advanced tab: opt-in custom tool endpoint (personal server-side tools for your agents).
struct AdvancedToolSettings: View {
    private static let templateRepo = "https://github.com/anupchavan/sesame-agent-tools"

    @AppStorage("sesameToolEnabled") private var enabled = false
    @AppStorage("sesameToolEndpoint") private var endpoint = ""
    @State private var secret = ""            // never read back; encrypted on set
    @State private var secretIsSet = ToolKey.isConfigured
    @State private var showHow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Custom tool endpoint").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.tx1)
                    Text("Let your agents call a personal tool you host")
                        .font(.system(size: 11)).foregroundStyle(Theme.tx3)
                }
            }
            .toggleStyle(.switch).tint(Theme.ax1)

            // Exactly what turning this on does.
            VStack(alignment: .leading, spacing: 6) {
                Text("What this changes")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tx2)
                Text(.init("""
                While on, each session the app silently sends your **location context field** \
                (`client.location_state.address`) a short note telling your agents a tool lives \
                at your endpoint, plus a **rotating access key** (HMAC of your shared secret, new \
                every 5 min). Agents fetch `your-url?q=<intent>&key=<key>` **server-side** and use \
                the reply. Nothing else is sent; it never appears in the chat. Off = no injection.
                """))
                .font(.system(size: 11.5)).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg2))

            field("Endpoint URL", placeholder: "https://you.github.io/sesame-agent-tools/tool") {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(!enabled)
            }

            field("Shared secret seed", placeholder: nil) {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField(secretIsSet ? "•••••••• (set — type to replace)" : "any long random string",
                                text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .disabled(!enabled)
                        .onSubmit(saveSecret)
                    Text(.init("Set this **once**. The app derives a fresh key from it every 5 min and sends that to the agent — you never type a key. Your endpoint uses the **same** secret to check keys. Encrypted on this Mac."))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.tx3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !secret.isEmpty {
                Button("Save secret", action: saveSecret).controlSize(.small)
            }

            DisclosureGroup(isExpanded: $showHow) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(.init("""
                    1. Open the template repo below and **Use this template** (or fork it).
                    2. Implement whatever tools you want; deploy to **GitHub Pages** (static) or a \
                    dynamic host (Cloudflare Worker / your server) for live tools.
                    3. Set the same shared secret in your endpoint's key check.
                    4. Paste your URL + secret here, turn this on.
                    5. In a chat or call, tell the agent once what the tool does — Sesame remembers \
                    it across sessions and devices.
                    """))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tx2)
                    .fixedSize(horizontal: false, vertical: true)
                    Link("Template & docs: anupchavan/sesame-agent-tools", destination: URL(string: Self.templateRepo)!)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .padding(.top, 8)
            } label: {
                Label("How to set this up", systemImage: "questionmark.circle")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ax1)
            }

            Spacer(minLength: 0)
        }
    }

    private func saveSecret() {
        ToolKey.setSecret(secret)
        secretIsSet = ToolKey.isConfigured
        secret = ""
    }

    private func field<C: View>(_ title: String, placeholder: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.tx2)
            content()
        }
    }
}
