import Foundation
import UIKit
import ZephraCore
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
            acceptsGeneration: false,
            // A Mac rendering a picture still queues another behind it, which is the whole of
            // what this state is photographed for: Generate live, Stop beside it.
            canQueue: true)
        snapshot.running = QueuedEntry(
            id: UUID(uuidString: "9D4C0F55-2B31-4E6A-A7C8-1F0B6E3D5A24")!,
            batchID: UUID(uuidString: "1E9C2A60-4E1D-4C35-9F0E-2C7B3A5D8E11")!,
            batchIndex: 0,
            modelID: snapshot.model.id,
            settings: GenerationSettings(
                prompt: "a red bicycle against a limestone wall",
                size: ImageSize(width: 1024, height: 1024), steps: 9, guidance: 0,
                seed: 8_123_447_209_115_664))
        // `acceptsWork` is the Mac's one gate — a folder being moved, a quit — and a run in
        // flight closes none of it, so a mid-run Mac still takes work.
        snapshot.acceptsWork = true
        return snapshot
    }

    /// A frame of the run the `generating` state is in the middle of.
    ///
    /// Drawn in code rather than kept as a file, for the reason the mid-run state is built in
    /// code: a real preview frame is a decode of a latent four steps into a ladder, and a
    /// photograph of one saved in the bundle would be a picture of a particular run rather
    /// than proof the canvas draws whatever arrives. What matters to the screenshot is that
    /// the bytes are a JPEG of the run's shape, soft, at preview size.
    static func frame() -> PreviewFrameDTO {
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors =
                [
                    UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.52, blue: 0.22, alpha: 1).cgColor,
                    UIColor(red: 0.35, green: 0.40, blue: 0.58, alpha: 1).cgColor,
                ] as CFArray
            guard
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                    locations: [0, 0.55, 1])
            else { return }
            context.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size.width, y: size.height),
                options: [])
        }
        return PreviewFrameDTO(
            jpeg: image.jpegData(compressionQuality: 0.8) ?? Data(),
            width: Int(size.width), height: Int(size.height), step: 4, steps: 9)
    }
}
