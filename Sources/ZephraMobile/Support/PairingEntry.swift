import Foundation
import ZephraLinkProtocol

/// The one place a pairing code turns into a payload, whichever of the three doors it came
/// through: the camera, the paste field, or a `zephra://pair` link opened from somewhere else.
///
/// `PairingURL.decode` already takes either the whole link or the bare payload and trims what
/// is round it. Two rules are added here, both of them about the person holding the phone: a
/// code has a life, and an expired one has to be refused here rather than at the far end,
/// where the Mac would only answer with a timeout; and whatever goes wrong has to come back as
/// a sentence, so a `JSONDecoder`'s complaint about a mistyped code never reaches the screen.
enum PairingEntry {
    /// What a code that is not one of ours says. One sentence, whether it was mistyped, cut in
    /// half, or a link to something else entirely: a person cannot act on the difference.
    nonisolated static let notACode = LinkError(
        code: .badRequest, reason: "That is not a Zephra pairing code.")

    /// The payload a scanned, pasted or opened code holds.
    ///
    /// - Throws: `LinkError`, always, with the words to put on screen.
    nonisolated static func parse(_ text: String, at date: Date = Date()) throws -> PairingPayload {
        let payload: PairingPayload
        do {
            payload = try PairingURL.decode(text)
        } catch let error as LinkError {
            throw error
        } catch {
            throw notACode
        }
        guard !payload.isExpired(at: date) else {
            throw LinkError(
                code: .refused,
                reason: "That pairing code has expired. Show a new one on your Mac.")
        }
        return payload
    }

    /// The sentence to show for whatever went wrong.
    ///
    /// A `LinkError` already carries the words to use — everything `parse` throws is one, and
    /// so is everything the far end refuses with. Anything else is a failure nobody wrote a
    /// sentence for, so it gets the one sentence that is true of all of them.
    nonisolated static func message(for error: Error) -> String {
        (error as? LinkError)?.reason ?? "That pairing code could not be read."
    }
}
