import Foundation
import ZephraLinkProtocol

/// Where a frozen launch's state comes from: two JSON files in the bundle, read with the very
/// decoder the wire uses.
///
/// Written out rather than built in code on purpose. A fixture that goes through
/// `LinkJSON.decoder()` is proof the DTOs still read what a Mac would send, which a Swift
/// literal could never be; `PreviewFixtureTests` is that proof run on every build.
extension MobilePreview {
    /// The Mac's state, as the fixture has it, or nil if the file is missing or unreadable.
    static func snapshot() -> StateSnapshot? {
        fixture(StateSnapshot.self, named: "preview-snapshot")
    }

    /// The page of library the fixture holds, or an empty page if the file cannot be read.
    static func library() -> [LibraryEntry] {
        fixture([LibraryEntry].self, named: "preview-library") ?? []
    }

    /// One fixture file, decoded.
    static func fixture<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? LinkJSON.decode(type, from: data)
    }

    /// The same snapshot with a run four steps into its ladder, which is the one state the
    /// fixture cannot hold: a file frozen mid-run would go stale the moment the numbers moved.
    static func midRun(_ snapshot: StateSnapshot?) -> StateSnapshot? {
        guard var snapshot else { return nil }
        snapshot.engine = EngineStateDTO(
            kind: .generating,
            phase: "Denoising",
            step: 4,
            steps: 9,
            fraction: 4.0 / 9.0,
            secondsPerStep: 0.71,
            modelID: snapshot.model.id,
            isBusy: true,
            isFinishing: false,
            acceptsGeneration: false)
        snapshot.running = QueuedEntry(
            id: UUID(uuidString: "9D4C0F55-2B31-4E6A-A7C8-1F0B6E3D5A24")!,
            batchID: UUID(uuidString: "1E9C2A60-4E1D-4C35-9F0E-2C7B3A5D8E11")!,
            batchIndex: 0,
            modelID: snapshot.model.id,
            prompt: "a red bicycle against a limestone wall",
            width: 1024,
            height: 1024,
            seed: 8_123_447_209_115_664,
            frames: 1)
        snapshot.acceptsWork = false
        return snapshot
    }
}
