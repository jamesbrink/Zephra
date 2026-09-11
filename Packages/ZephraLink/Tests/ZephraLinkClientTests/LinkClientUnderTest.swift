import Foundation
import Testing
import ZephraCore
import ZephraEngine
import ZephraLinkClient
import ZephraLinkProtocol

/// A phone, a Mac, and the road between them, stood up the way a test wants them.
@MainActor
struct LinkClientUnderTest {
    /// The phone.
    let client: LinkClient
    /// The Mac.
    let host: FakeHost
    /// What the phone keeps between launches.
    let store: MemoryLinkKeyStore

    /// A phone that has never paired, and a Mac showing a pairing code — or, with a nil secret,
    /// one showing none.
    init(secret: Data? = Data(repeating: 9, count: PairingSecret.byteCount)) {
        host = FakeHost(pairingSecret: secret)
        store = MemoryLinkKeyStore()
        client = LinkClient(store: store, roads: Self.roads(to: host), deviceName: "A Phone")
    }

    /// A phone that has paired already, and a Mac that knows it — or does not.
    init(remembering device: DeviceIdentity, knownToHost: Bool = true) {
        host = FakeHost(known: knownToHost ? [device.publicKeys] : [])
        let paired = PairedHost(
            name: "A Mac", keys: host.publicKeys,
            endpoints: [Endpoint(host: "127.0.0.1", port: 7777)], roomID: host.identity.roomID,
            pairedAt: Date())
        store = MemoryLinkKeyStore(identity: device, pairedHost: paired)
        client = LinkClient(store: store, roads: Self.roads(to: host), deviceName: "A Phone")
    }

    /// The code that Mac would show.
    func pairingCode(secret: Data = Data(repeating: 9, count: PairingSecret.byteCount))
        -> PairingPayload
    {
        PairingPayload(
            hostName: "A Mac", keys: host.publicKeys,
            endpoints: [Endpoint(host: "127.0.0.1", port: 7777)], secret: secret,
            expiresAt: Date().addingTimeInterval(PairingSecret.lifetime))
    }

    /// Roads that hand the phone one end of a pair and the Mac the other.
    private static func roads(to host: FakeHost) -> MemoryLinkRoads {
        let (phone, mac) = MemoryLinkConnection.pair()
        host.serve(mac)
        return MemoryLinkRoads { _ in phone }
    }
}

/// The values the client's suite builds a state out of.
enum ClientFixtures {
    static let date = Date(timeIntervalSince1970: 1_757_000_000)

    static var model: ModelSummary {
        ModelSummary(
            id: "z-image-turbo-4bit", displayName: "Z-Image Turbo", variantName: "4-bit",
            familyID: "z-image",
            capabilities: CapabilitiesSummary(
                ModelCapabilities(
                    sizeAlignment: 64, sizePresets: [ImageSize(width: 1024, height: 1024)],
                    sizeBounds: 512...1536, defaultSize: ImageSize(width: 1024, height: 1024),
                    stepBounds: 4...12, defaultSteps: 9, guidanceBounds: 0...0, defaultGuidance: 0,
                    supportsNegativePrompt: false, supportsSeed: true,
                    supportsReferenceImage: true, referenceStrengthBounds: 0.1...0.9,
                    defaultReferenceStrength: 0.6)))
    }

    static var snapshot: StateSnapshot {
        StateSnapshot(
            hostName: "A Mac", model: model, models: [model],
            engine: EngineStateDTO(kind: .ready, acceptsGeneration: true), queue: [], running: nil,
            history: [], availability: [:], downloads: [], today: [], libraryCount: 3,
            acceptsWork: true)
    }

    static func entry(_ name: String) -> LibraryEntry {
        LibraryEntry(
            fileName: name, record: nil, annotation: LibraryAnnotation(), isVideo: false,
            createdAt: date, width: 1024, height: 1024, fileSize: 2048, contentModifiedAt: date)
    }

    static var settings: GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse", size: ImageSize(width: 1024, height: 1024), steps: 9,
            guidance: 0, seed: 42)
    }
}
