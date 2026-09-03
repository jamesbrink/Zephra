import AppKit

/// The `NSTextView` behind the prompt: as tall as the band it sits in, and honest about focus.
///
/// Two things a stock text view is not. It is never shorter than its scroll view's clip, so a
/// click in the empty part of the prompt area lands on the text view and puts the caret at the
/// end, rather than on the scroll view and nowhere. And it says when it becomes and stops
/// being the first responder: the delegate's `textDidBeginEditing` and `textDidEndEditing` are
/// sent around edits, not around focus, so a click into the field and straight back out sends
/// neither, and the row's idea of where the caret is would drift from where it was.
final class CapsuleTextView: NSTextView {
    /// Called with `true` on becoming first responder and `false` on resigning it.
    var onFocusChange: ((Bool) -> Void)?

    override func layout() {
        if let clip = superview as? NSClipView, minSize.height != clip.bounds.height {
            minSize = CGSize(width: 0, height: clip.bounds.height)
            sizeToFit()
        }
        super.layout()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }
}
