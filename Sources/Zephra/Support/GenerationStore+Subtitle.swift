import ZephraEngine

/// The line under "Zephra" in the title bar: what the engine is doing, and how much work is
/// still outstanding.
extension GenerationStore {
    /// The window's subtitle.
    ///
    /// The count is what is waiting, not counting the one being rendered: the phase in front of
    /// it already says that one is under way, and counting it twice would read "1 queued"
    /// through every single generation.
    var windowSubtitle: String {
        let phase = isSwappingModel && state == .idle
            ? "Switching to \(descriptor.fullName)…"
            : state.subtitle(for: descriptor)
        guard !queue.isEmpty else { return phase }
        return "\(phase) · \(queue.count) queued"
    }
}
