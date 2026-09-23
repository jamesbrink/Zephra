import ZephraCore

/// What guidance above 1 needs to do anything: a negative prompt to steer away from.
///
/// Classifier-free guidance's second forward is what a guidance above 1 spends
/// (`MemoryGuard+Scaling`'s own reading of the same rule, which is what the Mac's memory guard
/// charges twice for): with nothing in the negative prompt the two branches diverge nowhere and
/// the second forward is paid for and does nothing. Shown only for a model where guidance is a
/// choice at all and where a negative prompt is one too — a distilled model draws neither
/// control and has nothing here to say.
enum GuidanceNote {
    /// "Guidance needs something to avoid.", or nil wherever the picture is already what the
    /// slider promises.
    static func text(
        guidance: Double, negativePrompt: String?, capabilities: ModelCapabilities
    ) -> String? {
        guard capabilities.adjustsGuidance, capabilities.supportsNegativePrompt else { return nil }
        guard guidance > 1, (negativePrompt ?? "").isEmpty else { return nil }
        return "Guidance needs something to avoid."
    }
}
