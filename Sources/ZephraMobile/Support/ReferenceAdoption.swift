import Foundation
import ZephraLinkProtocol

/// The one door every picture enters the reference well through.
///
/// The Mac has a type of this name for the same reason: a picture arrives from the camera
/// roll, from the Mac's library, and one day from a share sheet, and all three have to end up
/// as the same bytes with the same rules applied. It holds no state — the draft does — and it
/// encodes off the main actor, since a photo out of a phone's camera is twelve megapixels and
/// resizing one on the main actor is a frozen capsule somebody is watching.
enum ReferenceAdoption {
    /// Takes `data` — a photo, a PNG fetched off the Mac, anything ImageIO reads — into the
    /// well, naming where it came from when it came from the Mac's library.
    static func adopt(
        _ data: Data, origin: String?, into draft: PromptDraft,
        fitting capabilities: CapabilitiesSummary
    ) async {
        guard let picture = await Task.detached(operation: { ReferenceImageEncoder.picture(from: data) }).value
        else { return }
        draft.adopt(picture, origin: origin, fitting: capabilities.capabilities)
    }
}
