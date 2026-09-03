import Foundation
import ZephraCore

@testable import ZephraEngine

/// The three things a timeline is built out of, invented: a file the index knows about, an
/// image this session made, and a run of queue entries. No disk, no store, no window.
enum Fixtures {
    /// The moment every fixture is dated from, so "today" is a comparison a test can make
    /// without a calendar.
    static let epoch = Date(timeIntervalSince1970: 1_772_000_000)

    /// A path in a folder that does not exist, which is all a `LibraryItem`'s identity is.
    static func url(_ name: String) -> URL {
        URL(filePath: "/Zephra Timeline Tests/\(name).png")
    }

    /// An image as the store holds it, before it has been written.
    static func image(
        batch: UUID?,
        at offset: TimeInterval,
        url: URL?,
        prompt: String = "a red bicycle against a limestone wall",
        steps: Int = 4
    ) -> GeneratedImage {
        GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: prompt,
                size: ImageSize(width: 1024, height: 1024),
                steps: steps,
                guidance: 0,
                seed: 42
            ),
            modelID: ModelCatalog.default.id,
            createdAt: epoch.addingTimeInterval(offset),
            duration: .seconds(7),
            fileURL: url,
            batchID: batch
        )
    }

    /// A file the library index knows about, invented from a finished image.
    static func item(from image: GeneratedImage) -> LibraryItem {
        LibraryItem(
            url: image.fileURL ?? url(image.id.uuidString),
            collection: .generated,
            provenance: .generated(GenerationRecord(image)),
            fileSize: 1_800_000,
            contentModifiedAt: image.createdAt
        )
    }

    /// A file the library index knows about, described directly.
    static func item(
        prompt: String,
        at offset: TimeInterval,
        batch: UUID? = nil,
        steps: Int = 4
    ) -> LibraryItem {
        item(
            from: image(
                batch: batch,
                at: offset,
                url: url("\(prompt)-\(offset)"),
                prompt: prompt,
                steps: steps
            )
        )
    }

    /// One press of Generate's worth of queue entries, in the order they would run.
    static func queue(
        batch: UUID,
        count: Int,
        prompt: String = "a red bicycle against a limestone wall"
    ) -> [QueuedGeneration] {
        (0..<count).map { index in
            QueuedGeneration(
                model: ModelCatalog.default,
                settings: GenerationSettings(
                    prompt: prompt,
                    size: ImageSize(width: 1024, height: 1024),
                    steps: 4,
                    guidance: 0,
                    seed: UInt64(42 + index)
                ),
                batchID: batch,
                batchIndex: index
            )
        }
    }
}
