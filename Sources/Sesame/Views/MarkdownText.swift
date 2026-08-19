import SwiftUI

/// Lightweight markdown renderer for chat: bold/italic/code/links inline, plus bullet and
/// numbered lists and blank-line spacing between paragraphs. Good enough for agent replies;
/// avoids pulling in a full markdown engine.
struct MarkdownText: View {
    let text: String
    var color: Color = Theme.tx1

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {   // paragraph spacing
            ForEach(Array(blocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let s):
                    Text(inline(s)).foregroundStyle(color)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").foregroundStyle(color.opacity(0.7))
                        Text(inline(s)).foregroundStyle(color)
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(n).").foregroundStyle(color.opacity(0.7)).monospacedDigit()
                        Text(inline(s)).foregroundStyle(color)
                    }
                }
            }
        }
        .font(.system(size: 13.5))
        .lineSpacing(6)   // ≈ 1.5 line height
        .textSelection(.enabled)
    }

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
    }

    private func blocks() -> [Block] {
        // Each non-blank line is its own paragraph/list item; the VStack spacing separates
        // them. Lines that are genuinely one paragraph wrap inside their own Text (no \n).
        var result: [Block] = []
        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if let (n, rest) = numberedPrefix(trimmed) {
                result.append(.numbered(n, rest))
            } else {
                result.append(.paragraph(trimmed))
            }
        }
        return result
    }

    private func numberedPrefix(_ s: String) -> (Int, String)? {
        // "1. text" / "12) text"
        var digits = ""
        var idx = s.startIndex
        while idx < s.endIndex, s[idx].isNumber { digits.append(s[idx]); idx = s.index(after: idx) }
        guard !digits.isEmpty, idx < s.endIndex, s[idx] == "." || s[idx] == ")" else { return nil }
        let after = s.index(after: idx)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return (Int(digits) ?? 0, String(s[s.index(after: after)...]))
    }

    private func inline(_ s: String) -> AttributedString {
        // Inline-only markdown keeps ** * ` and [links], preserves the text otherwise.
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(s)
    }
}
