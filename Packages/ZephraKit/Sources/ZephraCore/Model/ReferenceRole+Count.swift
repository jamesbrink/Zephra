/// The same strings, said about several pictures.
///
/// Only `.reference` pluralises. The other three are single-picture roles by construction — a
/// clip has one first frame, a continuation one tail, a noised copy one picture to start from —
/// so they ignore the count and say what they always said. A model that reads several declares
/// `ModelCapabilities.referenceImageCount` past 1 and lands on `.reference`, which is why this
/// is the only case with a plural to offer.
extension ReferenceRole {
    /// The well's caption under the glyph, sentence case since it is a caption.
    public func wellCaption(count: Int) -> String {
        guard self == .reference, count > 1 else { return wellCaption }
        return "References"
    }

    /// The empty well's help text: what choosing or dropping pictures here does.
    public func emptyWellHelp(upTo: Int) -> String {
        guard self == .reference, upTo > 1 else { return emptyWellHelp }
        return "Choose pictures to edit, or drop them here"
    }

    /// The filled well's accessibility label.
    public func filledWellAccessibilityLabel(count: Int) -> String {
        guard self == .reference, count > 1 else { return filledWellAccessibilityLabel }
        return "Reference images"
    }

    /// `ReferenceImagePicker`'s open-panel message.
    public func openPanelMessage(upTo: Int) -> String {
        guard self == .reference, upTo > 1 else { return openPanelMessage }
        return "Choose pictures to edit"
    }

    /// The inspector's row label for where the pictures came from, which says how many once
    /// there is more than one: one row stands for the strip, and "Edited from" over three
    /// thumbnails reads as three separate edits.
    public func inspectorRowLabel(count: Int) -> String {
        guard self == .reference, count > 1 else { return inspectorRowLabel }
        return "Edited from \(count) pictures"
    }
}
