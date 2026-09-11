import Foundation
import ZephraLinkProtocol

/// What a connection costs this Mac before it has proved anything.
///
/// Opening a socket costs whoever opened it nothing, and finishing a handshake costs them a
/// pairing they do not have. So the plaintext stage is bounded twice: how many may sit in it,
/// and how long one may. Both are here rather than in a listener, which knows nothing of
/// handshakes and would have to be told; this way the relay road is bounded by the same rule
/// without being asked.
extension CompanionHost {
    /// How many connections may sit in the plaintext stage at once.
    ///
    /// Eight is far more than the phones in one house, and small enough that the ninth knock is
    /// refused rather than allocated.
    public static let unauthenticatedLimit = 8

    /// Starts one session over a connection that has just arrived, or refuses it.
    ///
    /// Only sessions still in the plaintext stage are counted: a house with nine paired phones
    /// talking is fine, and nine connections that have said nothing is not.
    func accept(_ connection: any LinkConnection) {
        guard unauthenticatedCount < CompanionHost.unauthenticatedLimit else {
            logger.notice("companion refused a connection: too many are still handshaking")
            Task { await connection.close() }
            return
        }
        let session = CompanionSession(connection: connection, host: self)
        sessions.append(session)
        session.start()
    }

    /// How many sessions have a connection but no channel yet.
    var unauthenticatedCount: Int {
        sessions.count { !$0.isAuthenticated }
    }
}
