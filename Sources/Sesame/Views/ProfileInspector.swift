import SwiftUI

/// Right-hand inspector: edit the account profile the agents read as context.
struct ProfileInspector: View {
    let agent: Agent
    @EnvironmentObject var store: AppStore
    @StateObject private var model = ProfileModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Nickname") {
                        TextField("What \(agent.name) calls you", text: $model.profile.nickname)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .modifier(FieldBox())
                            .onChange(of: model.profile.nickname) { model.markDirty() }
                    }

                    section("Gender") {
                        Picker("", selection: $model.profile.gender) {
                            Text("—").tag("")
                            Text("Male").tag("MALE")
                            Text("Female").tag("FEMALE")
                            Text("Non-binary").tag("NON_BINARY")
                            Text("Other").tag("OTHER")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Theme.tx2)
                        .onChange(of: model.profile.gender) { model.markDirty() }
                    }

                    section("Birthday") {
                        TextField("YYYY-MM-DD", text: $model.profile.birthday)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13).monospacedDigit())
                            .modifier(FieldBox())
                            .onChange(of: model.profile.birthday) { model.markDirty() }
                    }

                    section("Interests") {
                        TokenField(tokens: $model.profile.interests, placeholder: "Add interest (≤32 chars)",
                                   maxLength: 32, accent: agent.accent) { model.markDirty() }
                    }

                    section("Motivations") {
                        FlowChips(items: Motivation.allCases.map(\.rawValue),
                                  labels: Motivation.allCases.map(\.label),
                                  selected: $model.profile.motivations, accent: agent.accent) {
                            model.markDirty()
                        }
                    }

                    section("Custom motivations") {
                        TokenField(tokens: $model.profile.customMotivations, placeholder: "Add your own",
                                   maxLength: 120, accent: agent.accent) { model.markDirty() }
                    }

                    VStack(spacing: 12) {
                        Toggle("Allow training from calls", isOn: $model.profile.allowTrainingFromCalls)
                            .onChange(of: model.profile.allowTrainingFromCalls) { model.markDirty() }
                        Toggle("Product news emails", isOn: $model.profile.preferProductNewsEmails)
                            .onChange(of: model.profile.preferProductNewsEmails) { model.markDirty() }
                    }
                    .font(.system(size: 12.5))
                    .tint(agent.accent)
                    .foregroundStyle(Theme.tx1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .padding(.bottom, 18)
            }

            saveBar
        }
        .frame(width: 300)
        .background(Theme.bg1) // sidebars stay light
        .task { await model.load() }
    }

    @ViewBuilder
    private var saveBar: some View {
        Divider().overlay(Theme.ui1)
        HStack(spacing: 10) {
            if let status = model.status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(model.isError ? Theme.red : Theme.green)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await model.save() }
            } label: {
                Group {
                    if model.isSaving { ProgressView().controlSize(.small) }
                    else { Text("Save").font(.system(size: 12.5, weight: .medium)) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(model.dirty ? AnyShapeStyle(agent.accent) : AnyShapeStyle(Theme.ui2)))
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .disabled(!model.dirty || model.isSaving)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tx2)
            content()
        }
    }
}

/// Consistent input chrome across every field in the inspector.
struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.bg2))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.ui1, lineWidth: 1))
    }
}

@MainActor
final class ProfileModel: ObservableObject {
    @Published var profile = UserProfile()
    @Published var dirty = false
    @Published var isSaving = false
    @Published var status: String?
    @Published var isError = false
    private var loaded = false

    func markDirty() { if loaded { dirty = true; status = nil } }

    func load() async {
        guard !loaded else { return }
        do {
            profile = try await ProfileService.fetch()
            loaded = true
        } catch {
            status = "Couldn't load profile"
            isError = true
        }
    }

    func save() async {
        isSaving = true
        isError = false
        defer { isSaving = false }
        do {
            profile = try await ProfileService.update(profile)
            dirty = false
            status = "Saved"
        } catch {
            isError = true
            let raw = error.localizedDescription
            // Surface the server's readable reason (e.g. invalid motivation / birthday).
            status = raw.contains("Invalid") ? raw : "Save failed"
        }
    }
}
