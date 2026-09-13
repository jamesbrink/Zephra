import Foundation

/// Negotiated commands. A host advertises support before the phone sends any of these.
/// Responses are solicited; no new unsolicited event kind is sent to older clients.
public enum MultiHostCommand: Codable, Hashable, Sendable {
    case offer(StrictGeneration)
    case submit(StrictGeneration)
    case receipt(UUID)
    case previews(Bool)
    case cancelRun(UUID)
    case listing(offset: Int, limit: Int, revision: String?)
}
