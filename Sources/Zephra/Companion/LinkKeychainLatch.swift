import Foundation
import os

/// Which keychain this launch's secrets are spelled for, and the one way that answer may move.
///
/// `LinkKeychainKind` asks the question once from this build's signature; this holds the answer
/// for the store that was built from it. A build carrying a team identifier may still be refused
/// the data-protection keychain's entitlement, and the first call that comes back
/// `errSecMissingEntitlement` latches this to the legacy spelling for the rest of the launch —
/// rather than a probe, which would be one more keychain call in a path whose whole purpose is to
/// make fewer of them.
///
/// One per store rather than one per process, which is what makes it testable and what takes the
/// race out: the store is built once a launch, and the identity read and the devices read that
/// follow it share this object rather than a global somebody else may already have flipped.
nonisolated final class LinkKeychainLatch: Sendable {
    /// Whether a query should ask for the data-protection keychain right now.
    var usesDataProtection: Bool { state.withLock { $0 } }

    private let state: OSAllocatedUnfairLock<Bool>
    private let logger = Logger(subsystem: "io.zephra", category: "companion")

    /// A latch that starts where this build's signature says it should.
    init(usesDataProtection: Bool = LinkKeychainKind.usesDataProtection) {
        state = OSAllocatedUnfairLock(initialState: usesDataProtection)
    }

    /// Records that the data-protection keychain refused this build, so every call after this one
    /// is spelled the legacy way. Said once.
    func fallBackToLegacy() {
        let first = state.withLock { dataProtection -> Bool in
            defer { dataProtection = false }
            return dataProtection
        }
        guard first else { return }
        logger.info(
            "companion secrets: legacy keychain, since the data-protection one refused this build")
    }
}
