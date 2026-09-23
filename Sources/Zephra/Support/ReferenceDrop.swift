import AppKit
import Foundation
import UniformTypeIdentifiers
import ZephraCore
import ZephraEngine

/// Pictures dropped from the Finder, a browser, or another app, on their way to the well.
///
/// One handler for both drop targets, over item providers rather than two stacked
/// `dropDestination` modifiers whose precedence SwiftUI does not document. A file comes as a
/// URL and is read from disk; anything else comes as image bytes.
///
/// Every provider that is a picture is taken, not the first: a drop of five files is one choice
/// and lands as one `adoptReferences` claim, and the store takes as many as the model reads and
/// says in `referenceNote` when it took fewer.
enum ReferenceDrop {
    /// The types a drop target accepts.
    static let types: [UTType] = [.fileURL, .image]

    /// A provider on its way to the detached read. `NSItemProvider` is documented thread-safe,
    /// which the compiler cannot see; this wrapper is the one place that says so. Nonisolated,
    /// since the app's files default to the main actor and the read runs off it.
    private nonisolated struct DroppedProvider: @unchecked Sendable {
        let provider: NSItemProvider
        let type: UTType

        /// The picture this provider is carrying, or nil when it carries nothing macOS can read.
        func picture() async -> ReferencePicture? {
            let data = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            guard let data else { return nil }
            // A file macOS cannot read leaves whatever was there alone.
            guard type == .fileURL else { return ReferenceImageEncoder.picture(from: data) }
            return URL(dataRepresentation: data, relativeTo: nil)
                .flatMap { ReferenceImageEncoder.picture(contentsOf: $0) }
        }
    }

    /// Takes every provider that is a picture, encodes them in order, and hands them to `store`.
    /// Returns whether the drop was taken up, which is decided before the bytes are read.
    @MainActor
    static func handle(_ providers: [NSItemProvider], into store: GenerationStore) -> Bool {
        guard store.descriptor.capabilities.supportsReferenceImage else { return false }
        let dropped = providers.compactMap(picture(from:))
        guard !dropped.isEmpty else { return false }
        // The drop is a choice like any other, made now rather than when its bytes arrive: a
        // slow provider must not overtake a picture chosen from the library after it was
        // accepted, and Generate waits for it the way it waits for a library read.
        store.adoptReferences {
            var pictures: [ReferencePicture] = []
            for one in dropped {
                if let picture = await one.picture() { pictures.append(picture) }
            }
            return pictures
        }
        return true
    }

    /// The provider paired with the type it is being asked for, or nil when it is not a picture.
    private static func picture(from provider: NSItemProvider) -> DroppedProvider? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return DroppedProvider(provider: provider, type: .fileURL)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return DroppedProvider(provider: provider, type: .image)
        }
        return nil
    }
}
