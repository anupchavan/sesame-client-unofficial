import SwiftUI
import AppKit

/// Multiline chat input: Enter sends, Shift+Enter inserts a newline, the field grows with
/// content up to `maxHeight` and then scrolls internally.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxHeight: CGFloat = 140
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Use AppKit's fully-configured scrollable text view so the text container tracks width
        // and the view is properly editable/resizable (a hand-rolled NSTextView ends up with a
        // zero-width container and swallows keystrokes).
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 13.5)
        tv.textColor = NSColor(Theme.tx1)
        tv.insertionPointColor = NSColor(Theme.ax1)
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 2, height: 8)   // vertically centers a single line in 32pt
        tv.textContainer?.lineFragmentPadding = 0
        tv.string = text

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        DispatchQueue.main.async {
            context.coordinator.recomputeHeight()
            tv.window?.makeFirstResponder(tv)   // focus the field so you can type immediately
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.recomputeHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        init(_ p: GrowingTextView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            recomputeHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                if shift {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSend()
                }
                return true
            }
            return false
        }

        func recomputeHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let content = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let clamped = min(parent.maxHeight, max(32, content))
            scrollView?.hasVerticalScroller = content > parent.maxHeight + 0.5
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}
