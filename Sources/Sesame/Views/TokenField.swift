import SwiftUI

/// Editable list of string tokens shown as removable chips with an inline add field.
struct TokenField: View {
    @Binding var tokens: [String]
    let placeholder: String
    var maxLength: Int = 32
    let accent: Color
    var onChange: () -> Void = {}
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tokens.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tokens, id: \.self) { token in
                        HStack(spacing: 5) {
                            Text(token)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.tx1)
                                .lineLimit(1)
                            Button {
                                tokens.removeAll { $0 == token }
                                onChange()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.tx2)
                            }
                            .buttonStyle(.plain).focusEffectDisabled()
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.16)))
                    }
                }
            }
            HStack {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(add)
                if !draft.isEmpty {
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain).focusEffectDisabled()
                }
            }
            .modifier(FieldBox())
        }
    }

    private func add() {
        let t = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard !t.isEmpty, !tokens.contains(t) else { draft = ""; return }
        tokens.append(t)
        draft = ""
        onChange()
    }
}

/// Multi-select chips backed by a `[rawValue]` binding.
struct FlowChips: View {
    let items: [String]
    let labels: [String]
    @Binding var selected: [String]
    let accent: Color
    var onChange: () -> Void = {}

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, raw in
                let on = selected.contains(raw)
                Button {
                    if on { selected.removeAll { $0 == raw } } else { selected.append(raw) }
                    onChange()
                } label: {
                    Text(labels[i])
                        .font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? .white : Theme.tx2)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(on ? AnyShapeStyle(accent) : AnyShapeStyle(Theme.bg1)))
                }
                .buttonStyle(.plain).focusEffectDisabled()
            }
        }
    }
}

/// Simple wrapping HStack (chips flow onto multiple lines).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
