import AppKit
import Foundation
import UniformTypeIdentifiers
import ZephraEngine

/// A picture dropped from the Finder, a browser, or another app, on its way to the well.
///
/// One handler for both drop targets, over item providers rather than two stacked
/// `dropDestination` modifiers whose precedence SwiftUI does not document. A file comes as a
/// URL and is read from disk; anything else comes as image bytes.
enum ReferenceDrop {
    /// The types a drop target accepts.
    static let types: [UTType] = [.fileURL, .image]

    /// Takes the first provider that is a picture, encodes it, and hands it to `store`.
    /// Returns whether the drop was taken up, which is decided before the bytes are read.
    @MainActor
    static func handle(_ providers: [NSItemProvider], into store: GenerationStore) -> Bool {
        guard store.descriptor.capabilities.supportsReferenceImage,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                  || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return false }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL : .image
        // The drop's place in line is taken now, not when its bytes arrive: a slow provider
        // must not overtake a picture chosen from the library after it was accepted.
        let ticket = store.claimReference()
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data else { return }
            // A file macOS cannot read leaves whatever was there alone.
            let png: Data? =
                type == .fileURL
                ? URL(dataRepresentation: data, relativeTo: nil).flatMap(ReferenceImageEncoder.pngData(contentsOf:))
                : ReferenceImageEncoder.pngData(from: data)
            guard let png else { return }
            Task { @MainActor in store.useAsReference(png, ticket: ticket) }
        }
        return true
    }
}
