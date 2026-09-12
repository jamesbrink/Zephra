import Foundation
import ZephraLinkClient
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

    /// The sentence to show for whatever went wrong, preferring the one the client wrote.
    ///
    /// `LinkClient.pair(with:)` puts its own words on `connection` as it gives up — the Mac's
    /// refusal where there was one, and "Zephra could not reach halcyon" where no road opened —
    /// and those name the Mac, which no error thrown out of a socket ever will.
    ///
    /// A wait carries the sentence its failure did, so it reads the same either way: which of
    /// the two the client happens to be in is a matter of whether the reconnection has got as
    /// far as scheduling its next attempt, and that is nothing to change the words over.
    nonisolated static func message(for error: Error, connection: LinkConnectionState) -> String {
        if let reason = connection.reason { return reason }
        return message(for: error)
    }

    /// The sentence to show for whatever went wrong.
    ///
    /// A `LinkError` already carries the words to use — everything `parse` throws is one, and
    /// so is everything the far end refuses with. `LinkClientError` is this end's own, and has
    /// no words in it, so they are here. Anything else is a failure nobody wrote a sentence
    /// for, so it gets the one sentence that is true of all of them.
    nonisolated static func message(for error: Error) -> String {
        if let refusal = error as? LinkError { return refusal.reason }
        guard let ours = error as? LinkClientError else {
            return "That pairing code could not be read."
        }
        switch ours {
        case .notConnected: return "The connection to your Mac closed."
        case .notPaired: return "This phone is not paired with a Mac yet."
        case .unreachable:
            return "Zephra could not reach that Mac. Check that both are awake and on the "
                + "same network."
        case .notAdmitted:
            // The relay would not let this phone into the room. On the pairing screen that is
            // the same thing a person can act on as any other road that did not open: a Mac
            // with its code up has its room open, so this is a Mac that is not showing one.
            return "That Mac is not letting this phone in. Check that the code is still "
                + "showing on your Mac."
        case .timedOut: return "Your Mac did not answer in time."
        case .lost:
            return "A message between your Mac and this phone went missing. Try that again."
        case .unexpectedMessage, .unexpectedReply:
            return "Your Mac answered with something this version of Zephra does not understand."
        case .tooManyTransfers:
            return "Your Mac was sending too many pictures at once. Try that again."
        }
    }
}
