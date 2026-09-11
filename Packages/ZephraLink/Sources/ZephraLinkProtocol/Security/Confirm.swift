import Foundation

/// The handshake's last message: the phone proves it derived the same secrets too.
///
/// Its own message rather than the first sealed frame, so the Mac knows the channel is good
/// before it sends a snapshot, and a device with the wrong pairing secret is turned away with
/// a refusal rather than with an undecipherable frame.
public struct Confirm: Codable, Hashable, Sendable {
    /// The phone's proof: an HMAC over the transcript under the confirmation key.
    public var tag: Data

    /// Creates the closing message.
    public init(tag: Data) {
        self.tag = tag
    }
}
