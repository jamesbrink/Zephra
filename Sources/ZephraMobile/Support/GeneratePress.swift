import Foundation

/// Where one press of Generate has got to.
///
/// Three states rather than a pair of flags, because two of them are mutually exclusive and a
/// view holding both could show a refusal under a button it has just re-enabled. `sending` is
/// the round trip to the Mac: short on a local road, long enough over a relay that a second
/// press would arrive before the first was answered, and `enqueue` is answered from the run the
/// session already queued for that request id — so the press is held rather than de-duplicated
/// twice.
enum GeneratePress: Equatable, Sendable {
    /// Nothing in flight; the button is the button.
    case idle
    /// Asked, and waiting for the Mac to say what it did.
    case sending
    /// The Mac's own sentence, shown under the button until the next press.
    case refused(String)

    /// Whether a press is still in the air.
    var isSending: Bool { self == .sending }

    /// What to say under the button, or nil while there is nothing to say.
    var note: String? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}
