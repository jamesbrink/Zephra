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
    /// order (`Views/ModelMenu.swift`): a model that cannot be had at all says so first, then
    /// what a Mac too small for it would need, then a download's size, then how it would run
    /// here — "Tiles the decode", "Streams from disk" — and only then the plain availability
    /// label.
    ///
    /// The memory note comes **before** the download size for a row that cannot be pressed,
    /// which is the one place the two orders differ and is why the Mac's is the one to copy:
    /// the row is greyed by memory, so "Needs 23 GB" is what the greying means, and quoting a
    /// download that pressing the row would never start is the worse label. For a row that can
    /// be pressed the download still comes first, since the press is what starts it.
    func note(availability: AvailabilityDTO?) -> String? {
        if availability?.isObtainable == false { return availability?.label }
        if !isSelectable, let memoryNote { return memoryNote }
        if availability?.needsNetwork == true { return availability?.label }
        if let memoryNote { return memoryNote }
        return availability?.label
    }
}
