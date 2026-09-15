import Foundation

extension PromptDraft {
    /// Restore recorded settings without retaining a different draft's reference image.
    /// Source pixels are not part of library metadata; reusing settings starts without them.
    @discardableResult
    func reuse(_ entry: CachedEntry) -> Bool {
        guard let record = entry.entry.record else { return false }
        clearReference()
        settings = record.settings()
        modelID = record.modelID
        count = 1
        followedPrompt = nil
        preserveChosenSettings()
        return true
    }
}
