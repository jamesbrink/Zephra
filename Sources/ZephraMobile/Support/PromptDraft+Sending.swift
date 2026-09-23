import Foundation
import ZephraCore
import ZephraLinkProtocol

/// What of the well actually crosses, which is the Mac being spoken to's answer rather than the
/// phone's.
///
/// A file of its own beside `PromptDraft+ReferenceStrip`, because these two are about a
/// destination and everything there is about the well itself: the strip holds what somebody
/// chose, and this says how much of it the Mac at the other end will read.
extension PromptDraft {
    /// The pictures to send beside a request, as that Mac would read them.
    ///
    /// An older Mac's summary decodes `referenceImageCount` as `1...1`, so a phone talking to
    /// one sends its **first** picture and no others: the Mac would refuse the rest, and the
    /// phone would have paid for them over a relay before hearing so.
    func references(allowedBy summary: CapabilitiesSummary) -> [ReferencePicture] {
        let capabilities = summary.capabilities
        guard capabilities.supportsReferenceImage else { return [] }
        let room = min(capabilities.referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
        return ReferenceLimits.withinBudget(Array(references.filter(\.hasPixels).prefix(room)))
    }

    /// The first picture's bytes, or nil where the model would not read one. The older door,
    /// kept because a single-picture caller means exactly this.
    func reference(allowedBy summary: CapabilitiesSummary) -> Data? {
        references(allowedBy: summary).first?.data
    }
}
