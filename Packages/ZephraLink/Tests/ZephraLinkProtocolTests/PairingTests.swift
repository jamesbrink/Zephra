import CryptoKit
import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("A pairing code says who the Mac is and stops being true")
struct PairingTests {
    /// A payload with the most a code ever carries: four addresses and a long Mac name.
    static func payload(hostName: String = "James's MacBook Pro 16-inch M4") -> PairingPayload {
        let mac = DeviceIdentity()
        return PairingPayload(
            hostName: hostName,
            keys: mac.publicKeys,
            endpoints: [
                Endpoint(host: "192.168.1.100", port: 51820),
                Endpoint(host: "192.168.1.101", port: 51820),
                Endpoint(host: "10.0.0.42", port: 51820),
                Endpoint(host: "halcyon.local", port: 51820),
            ],
            secret: PairingSecret())
    }

    @Test("A code written and scanned back is the same payload")
    func urlRoundTrips() throws {
        let original = Self.payload()
        let decoded = try PairingURL.decode(try PairingURL.encode(original).absoluteString)
        #expect(decoded.hostName == original.hostName)
        #expect(decoded.keys == original.keys)
        #expect(decoded.endpoints == original.endpoints)
        #expect(decoded.roomID == original.roomID)
        #expect(decoded.secret == original.secret)
        #expect(abs(decoded.expiresAt.timeIntervalSince(original.expiresAt)) < 1)
    }

    @Test("The bare payload is accepted too, and whitespace around it is ignored")
    func barePayloadIsAccepted() throws {
        let original = Self.payload()
        let url = try PairingURL.encode(original)
        let bare = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "d" }?.value
        let decoded = try PairingURL.decode("  \(try #require(bare))\n")
        #expect(decoded.keys == original.keys)
    }

    @Test("A code with four addresses and a long name stays small enough to scan")
    func sizeBudgetIsMet() throws {
        // Measured at 522 characters for the whole link: a 32-character Mac name, four
        // addresses, both keys, the room, the secret and the expiry. The budget is 600,
        // which a version 11 QR code holds at the error correction a screen wants; the
        // margin is what a longer Mac name or a hostname endpoint spends.
        let url = try PairingURL.encode(Self.payload(hostName: String(repeating: "M", count: 32)))
        #expect(url.absoluteString.count <= 600)
        #expect(url.absoluteString.count > 300, "a payload this small means a field went missing")
    }

    @Test("Something that is not a Zephra code is refused")
    func foreignTextIsRefused() {
        #expect(throws: LinkError.self) { try PairingURL.decode("https://example.com/pair?d=x") }
        #expect(throws: LinkError.self) { try PairingURL.decode("zephra://open?d=abc") }
    }

    @Test("A secret stops being accepted after two minutes")
    func secretExpires() {
        let now = Date(timeIntervalSince1970: 1_757_000_000)
        let secret = PairingSecret(now: now)
        #expect(!secret.isExpired(at: now.addingTimeInterval(119)))
        #expect(secret.isExpired(at: now.addingTimeInterval(121)))
        #expect(secret.bytes.count == PairingSecret.byteCount)
    }

    @Test("A code carries at most four addresses")
    func endpointsAreCapped() {
        let extra = (0..<8).map { Endpoint(host: "10.0.0.\($0)", port: 51820) }
        let payload = PairingPayload(
            hostName: "Mac", keys: DeviceIdentity().publicKeys, endpoints: extra,
            secret: PairingSecret())
        #expect(payload.endpoints.count == PairingPayload.endpointLimit)
    }
}

