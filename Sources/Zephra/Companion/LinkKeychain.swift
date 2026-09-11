import Foundation
import ZephraLinkHost
import ZephraLinkProtocol

/// Where the companion link's secrets live between launches: this Mac's own identity, and the
/// phones it has agreed to talk to.
///
/// The facade the app holds, and the one place that decides *where* those two secrets are kept.
/// `LinkKeychainKind` answers that from this build's signature: a real signing identity gets the
/// keychain (`LinkKeychainStore`), and a build signed ad hoc gets two files under Application
/// Support (`LinkFileStore`), because the login keychain identifies an app by its signature and a
/// locally built Zephra has a new one every time it is built. Everything either store is asked
/// goes through `LinkSecretCache`, so a launch reads each secret once and writes only what is
/// worth a write.
///
/// It is still called `LinkKeychain` because that is what it is on the builds people run.
struct LinkKeychain: PairingStore, Sendable {
    /// The store this build may use, read and written through the one cache.
    private let secrets: LinkSecretCache

    /// The secrets this launch should read. A fresh start gets its own, wherever they live.
    ///
    /// The answer is passed in rather than read here: `FreshStart.current` is main-actor state
    /// in an app target isolated to the main actor by default, and this type is `Sendable` so
    /// that a session can hold it off the main actor.
    init(freshStart: FreshStart?) {
        secrets = LinkSecretCache(over: Self.store(freshStart: freshStart))
    }

    /// Which store this build's signature allows.
    static func store(freshStart: FreshStart?) -> any LinkSecretStore {
        switch LinkKeychainKind.current {
        case .file: LinkFileStore(freshStart: freshStart)
        case .dataProtection, .legacy: LinkKeychainStore(isFreshStart: freshStart != nil)
        }
    }

    /// This Mac's identity, made and stored the first time it is asked for.
    func identity() throws -> DeviceIdentity { try secrets.identity() }

    func load() throws -> [PairedDevice] { try secrets.load() }

    func save(_ devices: [PairedDevice]) throws { try secrets.save(devices) }

    /// Forgets the identity and every pairing, for a reset that should look like a Mac that has
    /// never linked.
    func removeAll() throws { try secrets.removeAll() }
}
