import Foundation
import ZephraCore
import ZephraEngine

/// Turning a library picture into reference bytes and putting it in the well.
///
/// An image that was itself edited from a picture hands back that picture, not itself: "use
/// this as a reference" on an edit almost always means "let me try that again from the same
/// starting point", and handing back the edit would compound one generation onto another.
///
/// Both doors read and re-encode off the main actor, through `ReferenceImageEncoder`, so a
/// large PNG is capped at 1024 pixels along its edge before anything holds it — the app would
/// otherwise carry the whole picture in memory, hash it, and write it into every image the
/// reference goes on to make. The one place that rule lives, so the menu button, the well's own
/// menu, and the picker sheet cannot drift apart on what "use as reference" means. Which choice
/// is current is the store's own bookkeeping (`GenerationStore.claimReference`); nothing here
/// holds state, so two stores could not trip over one another's choices.
enum ReferenceAdoption {
    /// Adopts a picture the caller already has as a `LibraryItem` — the menu button and the
    /// picker sheet's own selection, which both came from the index and so already know
    /// whether it carries a reference of its own.
    @MainActor
    static func adopt(_ item: LibraryItem, into store: GenerationStore) {
        store.adoptReference {
            if let source = item.referenceImage {
                return ReferenceImageEncoder.pngData(from: source)
            }
            return ReferenceImageEncoder.pngData(contentsOf: item.url)
        }
    }

    /// Adopts a picture this session made and the index may not have seen yet, by the same
    /// rule as a library item: one that was itself edited from a picture hands back that
    /// picture, and the bytes are re-encoded to the reference's own cap either way, so the
    /// canvas's menu means the same thing before and after the folder scan catches up.
    @MainActor
    static func adopt(_ image: GeneratedImage, into store: GenerationStore) {
        let source = image.settings.referenceImage ?? image.pngData
        store.adoptReference { ReferenceImageEncoder.pngData(from: source) }
    }

    /// Adopts a picture named only by its id — a drop of a `LibraryItemReference`, which
    /// carries nothing else. `LibraryItem.ID` is the standardized file path, so this reads the
    /// file directly rather than asking a `LibraryIndex` to resolve it first, which is what
    /// lets the well accept the drop without holding an index of its own.
    @MainActor
    static func adopt(id: LibraryItem.ID, into store: GenerationStore) {
        let url = URL(fileURLWithPath: id)
        store.adoptReference {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let reference = GenerationRecord.reference(in: data) {
                return ReferenceImageEncoder.pngData(from: reference)
            }
            return ReferenceImageEncoder.pngData(from: data)
        }
    }

    /// Puts `png` in the well, or clears it with nil, as a choice made right now: any library
    /// read still in flight is cancelled, so a slow picture can never land on top of a file, a
    /// drop, or a Clear that came after it.
    @MainActor
    static func use(_ png: Data?, into store: GenerationStore) {
        store.useAsReference(png, ticket: store.claimReference())
    }
}
