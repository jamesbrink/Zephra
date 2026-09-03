import AppKit
import SwiftUI

/// The prompt's text view: an `NSTextView` of our own, so the selection can be drawn by
/// `PromptLayoutManager` and the container's inset can be nothing at all.
///
/// SwiftUI's `TextEditor` is the same view underneath, out of reach. Building it here means
/// TextKit 1 — the layout manager is asked for by name, which is what selects it — and a text
/// container with no line fragment padding, so the text, the caret and the placeholder start
/// at the same edge without the negative padding the editor used to carry.
///
/// Focus is a plain binding: `true` makes the view first responder, and the view reports back
/// when it becomes or stops being one. Return breaks the line, as a text view does; the
/// window's key-equivalent pass hands Command-Return to the Generate button before the text
/// view sees it, as it did with `TextEditor`.
struct PromptTextView: NSViewRepresentable {
    /// The prompt.
    @Binding var text: String
    /// Whether the caret is in the field.
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = PromptLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = CapsuleTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.onFocusChange = { [coordinator = context.coordinator] focused in
            coordinator.parent.isFocused = focused
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // The Writing Tools badge hangs outside the capsule the moment anything is selected,
        // and a prompt is not prose to proofread.
        textView.writingToolsBehavior = .none
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        // Only when the two differ: writing the same string back would drop the selection
        // under the caret on every keystroke.
        if textView.string != text { textView.string = text }
        if isFocused, let window = textView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    /// Carries edits back to the binding and gives the view an undo stack of its own, so
    /// Edit > Undo means the prompt while the caret is here.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextView
        private let undo = UndoManager()

        init(_ parent: PromptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undo
        }
    }
}
