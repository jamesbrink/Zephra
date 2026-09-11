import Foundation
import ZephraLinkProtocol

/// The one place a pairing code turns into a payload, whichever of the three doors it came
/// through: the camera, the paste field, or a `zephra://pair` link opened from somewhere else.
///
/// `PairingURL.decode` already takes either the whole link or the bare payload and trims what
/// is round it, so the only rule added here is the one it cannot know: a code has a life, and
/// an expired one has to be refused here rather than at the far end, where the Mac would only
/// answer with a timeout.
enum PairingEntry {
    /// The payload a scanned, pasted or opened code holds.
    ///
    /// - Throws: `LinkError` with a sentence to put on screen, for a code that is not one of
    ///   ours and for a code whose time is up.
    nonisolated static func parse(_ text: String, at date: Date = Date()) throws -> PairingPayload {
        let payload = try PairingURL.decode(text)
        guard !payload.isExpired(at: date) else {
            throw LinkError(
                code: .refused,
                reason: "That pairing code has expired. Show a new one on your Mac.")
        }
        return payload
    }

    /// The sentence to show for whatever went wrong.
    ///
    /// A `LinkError` already carries the words to use, and anything else is a failure nobody
    /// wrote a sentence for, so it gets the one sentence that is true of all of them.
    nonisolated static func message(for error: Error) -> String {
        (error as? LinkError)?.reason ?? "That pairing code could not be read."
    }
}
