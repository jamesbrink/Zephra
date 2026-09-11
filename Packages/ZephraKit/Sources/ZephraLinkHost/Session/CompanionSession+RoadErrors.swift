import Foundation
import ZephraLinkProtocol

/// What the road under a session refuses, where the road can refuse anything.
///
/// Only the relay can: an `error` frame after the join leaves the connection open, so this Mac
/// carries on none the wiser while the phone is one frame short. Nothing else in the link knows
/// it happened, which is why it is logged here rather than swallowed under the transport.
extension CompanionSession {
    /// Watches the road's refusals for the life of the session, logging each at error.
    func watchRoadErrors() -> Task<Void, Never> {
        let refusals = connection.relayErrors()
        return Task { @MainActor [weak self] in
            for await reason in refusals {
                self?.logger.error(
                    "companion had a frame refused by the relay: \(reason, privacy: .public)")
            }
        }
    }
}
