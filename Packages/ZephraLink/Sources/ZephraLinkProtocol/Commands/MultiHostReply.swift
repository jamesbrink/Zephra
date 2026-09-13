import Foundation

/// Only sent in response to a negotiated multi-host command.
public enum MultiHostReply: Codable, Hashable, Sendable {
    case offer(HostOffer)
    case receipt(GenerationReceipt)
    case listing(LibraryListing)
}
