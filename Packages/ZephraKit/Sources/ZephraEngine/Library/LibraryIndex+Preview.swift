import Foundation
import ZephraCore

/// An index with no folder behind it, for SwiftUI previews and the screenshot builds driven by
/// `ZEPHRA_PREVIEW_STATE`.
///
/// Nothing here touches the file system: `isLive` is false, so `start()`, a scan and every write
/// return without looking for a disk. What it holds is invented, spread over several days and
/// two models so a grid has headings and a sidebar has counts.
extension LibraryIndex {
    /// An index holding `count` invented images, newest first.
    public static func preview(count: Int = 24) -> LibraryIndex {
        let index = LibraryIndex(
            library: ImageLibrary(root: URL(filePath: "/Zephra Previews", directoryHint: .isDirectory)))
        index.isLive = false
        let albums = [Album(name: "Harbours"), Album(name: "Portraits")]
        index.albums = albums
        index.items = (0..<count).map { offset in
            previewItem(offset: offset, albums: albums)
        }
        index.reproject()
        return index
    }

    private static let previewPrompts = [
        "A lighthouse at dusk, fog rolling in over black rocks",
        "A harbour in the rain, sodium lamps on wet stone",
        "A greenhouse in winter, low sun through misted glass",
        "A tram crossing a bridge at blue hour",
    ]

    private static func previewItem(offset: Int, albums: [Album]) -> LibraryItem {
        let model = offset.isMultiple(of: 3)
            ? (ModelCatalog.all.last ?? ModelCatalog.default) : ModelCatalog.default
        let created = Date(timeIntervalSince1970: 1_772_000_000)
            .addingTimeInterval(-Double(offset) * 9_000)
        let seed = UInt64(0x5EED_0000) &+ UInt64(offset)
        let image = GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: previewPrompts[offset % previewPrompts.count],
                size: model.capabilities.defaultSize,
                steps: model.capabilities.defaultSteps,
                guidance: model.capabilities.defaultGuidance,
                seed: seed
            ),
            modelID: model.id,
            createdAt: created,
            duration: .seconds(6.9 + Double(offset % 5))
        )
        var annotation = LibraryAnnotation(
            isFavourite: offset.isMultiple(of: 4),
            tags: offset.isMultiple(of: 2) ? ["night"] : []
        )
        if offset.isMultiple(of: 5), let album = albums.first {
            annotation.albums = [LibraryAnnotation.Membership(id: album.id, name: album.name)]
        }
        return LibraryItem(
            url: URL(filePath: "/Zephra Previews/zephra-preview-\(offset).png"),
            collection: .generated,
            provenance: .generated(GenerationRecord(image)),
            annotation: annotation,
            fileSize: 1_800_000,
            contentModifiedAt: created
        )
    }
}
