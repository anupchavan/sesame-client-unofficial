import SwiftUI

/// Floating call card shown at the top of the chat during a voice call.
struct CallCard: View {
    let agent: Agent
    @EnvironmentObject var call: CallManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.green)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tx1)
                statusLine
            }
            Spacer(minLength: 20)

            Button(action: { call.toggleMute() }) {
                Image(systemName: call.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(call.isMuted ? .white : Theme.tx1)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(call.isMuted ? AnyShapeStyle(Theme.tx3) : AnyShapeStyle(Theme.bg3)))
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help(call.isMuted ? "Unmute" : "Mute")

            Button(action: { call.end() }) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.red))
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .help("End call")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.ui1, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        )
        .frame(maxWidth: 380)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch call.state {
        case .connecting:
            Text("connecting…").font(.system(size: 11)).foregroundStyle(Theme.tx2)
        case .ringing:
            Text("ringing…").font(.system(size: 11)).foregroundStyle(Theme.tx2)
        case .active(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                let s = Int(context.date.timeIntervalSince(since))
                Text(String(format: "%d:%02d", s / 60, s % 60))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.green)
            }
        case .ended(let reason):
            Text(reason ?? "ended").font(.system(size: 11)).foregroundStyle(Theme.red)
        case .none:
            EmptyView()
        }
    }
}
