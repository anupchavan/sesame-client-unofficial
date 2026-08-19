import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            if store.showSidebar {
                SidebarView()
                    .frame(width: 264)
                    .transition(.move(edge: .leading))
                Rectangle()
                    .fill(Theme.ui1)
                    .frame(width: 1)
            }
            ChatView(vm: store.vm(store.selected))
                .id(store.selected)
                .clipped() // keep the header bar's shadow inside the chat column

            if store.showInspector {
                Rectangle().fill(Theme.ui1).frame(width: 1)
                ProfileInspector(agent: store.selected)
                    .id(store.selected)
                    .transition(.move(edge: .trailing))
            }
        }
        .ignoresSafeArea(.container, edges: .top) // content owns the (transparent) titlebar area
        .background(Theme.bg1)
        .sheet(isPresented: $store.showSettings) { SettingsView() }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer() // traffic lights sit at the left of this bar
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
                .help("Hide sidebar")
            }
            .frame(height: 52)
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {   // gap between conversations
                ForEach(Agent.allCases) { agent in
                    SidebarRow(vm: store.vm(agent), selected: store.selected == agent)
                        .onTapGesture {
                            store.selected = agent
                            store.vm(agent).unread = 0
                        }
                }
            }
            .padding(.top, 4)

            Spacer()

            Button {
                store.showSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.tx2)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
        }
        .frame(maxHeight: .infinity)
        .background(Theme.bg1) // sidebars stay light; chat canvas is the grey
    }
}

struct SidebarRow: View {
    @ObservedObject var vm: ChatViewModel
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.agent.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.tx1)
                Text(vm.isTyping ? "typing…" : vm.lastPreview)
                    .font(.system(size: 12))
                    .foregroundStyle(vm.isTyping ? vm.agent.accent : Theme.tx2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if vm.unread > 0 && !selected {
                Text("\(vm.unread)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(vm.agent.accent))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Theme.bg3 : (hovering ? Theme.bg3.opacity(0.5) : .clear))
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

