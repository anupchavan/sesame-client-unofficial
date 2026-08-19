import SwiftUI
import AppKit

/// Obsidian Minimal palette (kepano/obsidian-minimal theme.css), resolved from its
/// hsl() variables. Light: base 0/0%/96%, accent 201/17%/50%. Dark: base l 15%, accent l 60%.
enum Theme {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    // Backgrounds
    static let bg1 = dyn(hex(0xFFFFFF), hex(0x262626))   // primary
    static let bg2 = dyn(hex(0xF5F5F5), hex(0x212121))   // secondary (sidebar)
    static let bg3 = dyn(hex(0x757575, 0.12), hex(0x8C8C8C, 0.12)) // active/hover

    // Borders / UI
    static let ui1 = dyn(hex(0xE6E6E6), hex(0x363636))
    static let ui2 = dyn(hex(0xD6D6D6), hex(0x454545))
    static let ui3 = dyn(hex(0xC2C2C2), hex(0x595959))

    // Text
    static let tx1 = dyn(hex(0x0F0F0F), hex(0xD1D1D1))   // primary
    static let tx2 = dyn(hex(0x757575), hex(0x999999))   // muted
    static let tx3 = dyn(hex(0xB5B5B5), hex(0x595959))   // faint
    static let tx4 = dyn(hex(0x5C5C5C), hex(0xA6A6A6))

    // Accent hsl(201, 17%)
    static let ax1 = dyn(hex(0x6A8695), hex(0x889EAA))
    static let ax2 = dyn(hex(0x59717D), hex(0xA0B1BB))
    static let ax3 = dyn(hex(0x7C95A2), hex(0x7992A0))

    // Fixed extended palette (same in both modes)
    static let red    = Color(nsColor: hex(0xD04255))
    static let orange = Color(nsColor: hex(0xD5763F))
    static let yellow = Color(nsColor: hex(0xE5B567))
    static let green  = Color(nsColor: hex(0xA8C373))
    static let cyan   = Color(nsColor: hex(0x73BBB2))
    static let blue   = Color(nsColor: hex(0x6C99BB))
    static let purple = Color(nsColor: hex(0x9E86C8))
    static let pink   = Color(nsColor: hex(0xB05279))
}
