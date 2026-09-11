import Foundation
import ZephraLinkHost
import os

/// One read of each secret per launch, and as few writes as the link can get away with.
///
/// Every call the companion makes goes through here, because the store underneath may be the
/// keychain and a keychain call is not free: on a build whose signature the login keychain does
/// not recognise it is a password prompt, and `SecItemCopyMatching` does not return until
/// somebody answers one. Three rules, in order of how much they buy:
///
/// - **Read once.** The identity and the device list are read at launch and kept for the
///   process. Nothing re-reads after a write either: what was written is what is there.
/// - **Write a pairing straight through.** A phone paired or revoked is a real change and is
///   persisted at once, since a coalesced pairing is a pairing lost to a crash.
/// - **Rate-limit what is only cosmetic.** `lastSeen` moves every time a phone reconnects and
///   nothing depends on it being exact, so a list that differs from the stored one by nothing
///   else is written at most once a minute; the deferred value lands on the timer or with the
///   next real change, whichever comes first.
final class LinkSecretCache: LinkSecretStore, @unchecked Sendable {
    /// The store this cache is over: the keychain, or files for a build signed ad hoc.
    private let backing: any LinkSecretStore
    /// Everything read or written so far, behind one lock, since a session reads this off the
    /// main actor while the host writes it on it.
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// What the clock says, injected so the rate limit is tested without waiting a minute.
    private let now: @Sendable () -> Date
    /// Where a deferred write is made.
    private let queue = DispatchQueue(label: "io.zephra.link.secrets", qos: .utility)

    /// How long a list that differs only in `lastSeen` waits before it is worth a write.
    static let cosmeticInterval: TimeInterval = 60

    init(over backing: any LinkSecretStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.backing = backing
        self.now = now
    }

    func identityBytes() throws -> Data? {
        if let cached = state.withLock({ $0.identity }) { return cached }
        let bytes = try backing.identityBytes()
        state.withLock { $0.identity = .some(bytes) }
        return bytes
    }

    func writeIdentity(_ bytes: Data) throws {
        try backing.writeIdentity(bytes)
        state.withLock { $0.identity = .some(bytes) }
    }

    func load() throws -> [PairedDevice] {
        if let cached = state.withLock({ $0.devices }) { return cached }
        let devices = try backing.load()
        // The launch read counts as the last write: a phone that reconnects in the first minute
        // moves `lastSeen` and is not worth a second call before the app has drawn a window.
        state.withLock {
            $0.devices = devices
            $0.written = devices
            $0.lastWrite = now()
        }
        return devices
    }

    func save(_ devices: [PairedDevice]) throws {
        let next = state.withLock { state -> Write in
            state.devices = devices
            if state.written == devices { return .nothing }
            guard state.isCosmetic(devices), let since = state.lastWrite else { return .now }
            let waited = now().timeIntervalSince(since)
            return waited >= Self.cosmeticInterval ? .now : .later(Self.cosmeticInterval - waited)
        }
        switch next {
        case .nothing: return
        case .now: try writeThrough(devices)
        case .later(let delay): deferWrite(by: delay)
        }
    }

    func removeAll() throws {
        try backing.removeAll()
        state.withLock { $0 = State() }
    }

    /// Writes a deferred list if one is still waiting, which is what the timer above does when
    /// the minute is up and what a test asks for rather than waiting one.
    func flush() {
        let devices = state.withLock { state -> [PairedDevice]? in
            guard let devices = state.devices, devices != state.written else { return nil }
            return devices
        }
        guard let devices else { return }
        try? writeThrough(devices)
    }

    /// Persists a list now and records that it is what the store holds.
    private func writeThrough(_ devices: [PairedDevice]) throws {
        try backing.save(devices)
        state.withLock {
            $0.written = devices
            $0.lastWrite = now()
        }
    }

    /// Leaves a cosmetic change for later, one timer at a time.
    private func deferWrite(by delay: TimeInterval) {
        let scheduled = state.withLock { state -> Bool in
            defer { state.isDeferred = true }
            return state.isDeferred
        }
        guard !scheduled else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            state.withLock { $0.isDeferred = false }
            flush()
        }
    }

    /// What a `save` is worth: nothing at all, a call now, or a call once the minute is up.
    private enum Write {
        case nothing
        case now
        case later(TimeInterval)
    }

    /// What this cache knows.
    private struct State {
        /// The identity as read, where the outer optional is "has been read at all".
        var identity: Data??
        /// The device list as it stands, or nil before it has been read.
        var devices: [PairedDevice]?
        /// The device list as the store underneath holds it.
        var written: [PairedDevice]?
        /// When the store underneath last agreed with `written`.
        var lastWrite: Date?
        /// Whether a deferred write is already on the queue.
        var isDeferred = false

        /// Whether a list differs from the stored one by `lastSeen` alone, which is what a
        /// phone reconnecting changes and nothing on screen depends on to the second.
        func isCosmetic(_ devices: [PairedDevice]) -> Bool {
            guard let written, written.count == devices.count else { return false }
            return zip(written, devices).allSatisfy { stored, fresh in
                var stripped = fresh
                stripped.lastSeen = stored.lastSeen
                return stripped == stored
            }
        }
    }
}
