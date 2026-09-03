import ZephraEngine

/// The line under "Zephra" in the title bar: what the engine is doing, and how much work is
/// still outstanding.
extension GenerationStore {
    /// The window's subtitle.
    ///
    /// The count is everything still to come, the image being rendered included, because that
    /// is the question the number answers: how much is left. The queue itself no longer holds
    /// the running generation, so it has to be added back.
    var windowSubtitle: String {
        let phase = isSwappingModel && state == .idle
            ? "Switching to \(descriptor.fullName)…"
            : state.subtitle(for: descriptor)
        let outstanding = queue.count + (running == nil ? 0 : 1)
        guard outstanding > 0 else { return phase }
        return "\(phase) · \(outstanding) queued"
    }
}
