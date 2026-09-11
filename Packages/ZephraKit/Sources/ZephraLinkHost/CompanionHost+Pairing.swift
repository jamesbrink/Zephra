import Foundation
import ZephraLinkProtocol

/// Who may talk to this Mac: the code on screen, the list behind it, and taking a device off it.
extension CompanionHost {
    /// Puts a fresh code up and answers what it should say.
    ///
    /// A new secret every time, never a reused one: the code is photographed off a screen and is
    /// a secret only for as long as the screen remembers it, which is the two minutes
    /// `PairingSecret` gives it. The addresses are asked for now rather than at launch, so a
    /// laptop that has changed networks publishes the one it is actually on.
    @discardableResult
    public func beginPairing() -> PairingPayload {
        let secret = PairingSecret()
        self.secret = secret
        pairingFailures = 0
        pairingNote = nil
        let payload = PairingPayload(
            hostName: hostName, keys: identity.publicKeys, endpoints: endpoints(), secret: secret)
        pairing = payload
        logger.info("companion pairing open until \(secret.expiresAt, privacy: .public)")
        return payload
    }

    /// Takes the code down. A device that has not finished its handshake by now is refused.
    public func endPairing() {
        secret = nil
        pairing = nil
        pairingFailures = 0
    }

    /// One device answered the code wrongly.
    ///
    /// The secret behind a code is a thing to be guessed at, and the code sits on screen for two
    /// whole minutes: leaving it up while something works through answers is the one way it is
    /// cheap to attack. The third wrong answer burns the secret, takes the code down and leaves
    /// a line where it was, so the person sees what happened rather than a code that quietly
    /// stopped working. A wrong tag from a device that was *reconnecting* is not counted: no
    /// code is being guessed at, and the session is refused on its own.
    func pairingFailed() {
        guard secret != nil else { return }
        pairingFailures += 1
        guard pairingFailures >= CompanionHost.pairingAttemptLimit else { return }
        endPairing()
        pairingNote = "The pairing code was answered wrongly three times, so it was taken down. Show a new one to try again."
        logger.notice("companion pairing ended after \(CompanionHost.pairingAttemptLimit, privacy: .public) wrong answers")
    }

    /// The secret a handshake may be salted with right now, or nil when no code is up or the one
    /// that is has run out. Read at the moment a `Hello` lands, so an expired code refuses the
    /// connection without anything having to take the code down first.
    var liveSecret: Data? {
        guard let secret, !secret.isExpired() else { return nil }
        return secret.bytes
    }

    /// Whether a device's static keys are ones this Mac has already agreed to.
    func isKnown(_ keys: DevicePublicKeys) -> Bool {
        devices.contains { $0.keys == keys }
    }

    /// The signing keys the relay admits a guest out of.
    ///
    /// Every paired device, the most recently seen first, and at most `RelayJoin.allowLimit` of
    /// them, which is all the relay will take: a Mac with more phones than that admits the ones
    /// actually in use rather than whichever the keychain happened to list first. An empty list
    /// admits nobody, which is what a Mac that has paired nothing should do.
    public var relayAllowList: [Data] {
        devices
            .sorted { ($0.lastSeen ?? $0.pairedAt) > ($1.lastSeen ?? $1.pairedAt) }
            .prefix(RelayJoin.allowLimit)
            .map(\.keys.signing)
    }

    /// Records a device the handshake has just paired, and takes the code down.
    ///
    /// One code pairs one phone. Leaving it up would mean a photograph of it taken across the
    /// room pairs a second, and the person who put it up has already got what they asked for.
    func devicePaired(_ keys: DevicePublicKeys, name: String) {
        guard !isKnown(keys) else { return markSeen(keys) }
        devices.append(
            PairedDevice(keys: keys, name: name, pairedAt: Date(), lastSeen: Date()))
        persistDevices()
        endPairing()
        logger.info("companion paired a device named \(name, privacy: .public)")
    }

    /// Notes that a known device has come back.
    func markSeen(_ keys: DevicePublicKeys) {
        guard let index = devices.firstIndex(where: { $0.keys == keys }) else { return }
        devices[index].lastSeen = Date()
        persistDevices()
    }

    /// Withdraws a pairing and closes whatever that device is doing.
    ///
    /// The list is written before the sessions are closed, so a phone that reconnects the
    /// instant it is dropped is refused by `isKnown` rather than racing the save.
    public func revoke(_ device: PairedDevice) async {
        devices.removeAll { $0.keys == device.keys }
        persistDevices()
        let closing = sessions.filter { $0.belongs(to: device.keys) }
        for session in closing {
            await session.close(
                telling: LinkError(
                    code: .revoked, reason: "This Mac has stopped sharing with this device."))
        }
    }

    /// Writes the list back. A store that will not save is reported and nothing else: the
    /// pairing still holds for this launch, and refusing it because a keychain is locked would
    /// be a worse answer than one that does not survive a relaunch.
    private func persistDevices() {
        do {
            try pairings.save(devices)
        } catch {
            logger.error("companion pairings could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
