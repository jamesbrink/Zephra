import CryptoKit
import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("A device keeps the same identity across a relaunch")
struct DeviceIdentityTests {
    @Test("An identity written out and read back is the same identity")
    func identityRoundTrips() throws {
        let original = DeviceIdentity()
        let restored = try DeviceIdentity(rawRepresentation: original.rawRepresentation)
        #expect(restored.publicKeys == original.publicKeys)
        #expect(original.rawRepresentation.count == DeviceIdentity.rawByteCount)
    }

    @Test("Bytes that are not an identity are refused")
    func shortBytesAreRefused() {
        #expect(throws: LinkError.self) {
            try DeviceIdentity(rawRepresentation: Data(count: 32))
        }
    }

    @Test("The room is the first sixteen bytes of the signing key's hash, as hex")
    func roomFollowsTheSigningKey() throws {
        let identity = DeviceIdentity()
        let digest = SHA256.hash(data: identity.publicKeys.signing)
        let expected = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        #expect(identity.roomID.rawValue == expected)
        #expect(identity.roomID.rawValue.count == 32)
        #expect(identity.roomID == identity.publicKeys.roomID)
    }

    @Test("Two devices are in different rooms")
    func roomsDiffer() {
        #expect(DeviceIdentity().roomID != DeviceIdentity().roomID)
    }
}
