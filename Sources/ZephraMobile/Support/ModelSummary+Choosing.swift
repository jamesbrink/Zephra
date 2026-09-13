import ZephraLinkProtocol

/// What one row of the model menu offers, from the two answers the Mac stamped: whether the
/// model can be obtained there, and whether that Mac can hold it.
///
/// Pure, and here rather than inside the menu, for the reason `MemoryFit+Label` is not inside
/// the Mac's own menu: the words and the gate are one answer, and a view that worked either out
/// for itself could disagree with the Mac about which models are on offer.
extension ModelSummary {
    /// Whether the Mac would take a press of this row. A model it cannot hold is never loaded
    /// and never downloaded, so offering the press would only earn a refusal.
    func isChoosable(availability: AvailabilityDTO?) -> Bool {
        isSelectable && availability?.isObtainable != false
    }

    /// The line beside the name, or nil when there is nothing worth saying, in the Mac's own
    /// order (`Views/ModelMenu.swift`): a model that cannot be had at all says so before
    /// anything about memory, and a download's size has to be on screen before the row is
    /// pressed, so both come first; then how it would run here — "Tiles the decode", "Streams
    /// from disk", "Needs 23 GB" — and only then the plain availability label.
    func note(availability: AvailabilityDTO?) -> String? {
        if availability?.isObtainable == false { return availability?.label }
        if availability?.needsNetwork == true { return availability?.label }
        if let memoryNote { return memoryNote }
        return availability?.label
    }
}
