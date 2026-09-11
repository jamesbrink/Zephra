import Foundation
import ZephraCore
import ZephraEngine
import Testing
@testable import ZephraLinkProtocol

/// The values every suite here builds on, in one place so a change to a DTO's shape is one
/// edit rather than twenty.
enum LinkFixtures {
    /// A fixed date, so a golden string stays golden.
    static let date = Date(timeIntervalSince1970: 1_757_000_000)

    /// A picture model's capabilities, small enough to read in a failure message.
    static var capabilities: ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: 64,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...1536,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 4...12,
            defaultSteps: 9,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true,
            referenceStrengthBounds: 0.1...0.9,
            defaultReferenceStrength: 0.6)
    }

    /// One model summary.
    static var model: ModelSummary {
        ModelSummary(
            id: "z-image-turbo-4bit", displayName: "Z-Image Turbo", variantName: "4-bit",
            familyID: "z-image", capabilities: CapabilitiesSummary(capabilities))
    }

    /// One settings value with no picture in it.
    static var settings: GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse", size: ImageSize(width: 1024, height: 1024), steps: 9,
            guidance: 0, seed: 42)
    }

    /// One provenance record.
    static var record: GenerationRecord {
        GenerationRecord(
            GeneratedImage(
                pngData: Data([0x89, 0x50]), settings: settings, modelID: model.id,
                createdAt: date, duration: .seconds(12.5), fileURL: nil, batchID: nil))
    }

    /// One library entry.
    static var entry: LibraryEntry {
        LibraryEntry(
            fileName: "lighthouse.png", record: record, annotation: LibraryAnnotation(),
            isVideo: false, createdAt: date, width: 1024, height: 1024, fileSize: 2048,
            contentModifiedAt: date)
    }

    /// One queue row.
    static func queued(id: UUID, batchID: UUID) -> QueuedEntry {
        QueuedEntry(id: id, batchID: batchID, batchIndex: 0, modelID: model.id, settings: settings)
    }

    /// A value written and read back through the one spelling every envelope body uses.
    static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try LinkJSON.decode(T.self, from: LinkJSON.encode(value))
    }
}
