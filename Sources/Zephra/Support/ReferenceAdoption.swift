import Foundation
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
/// menu, and the picker sheet cannot drift apart on what "use as reference" means.
enum ReferenceAdoption {
    /// The read in flight. A second choice cancels the first, so a slow picture chosen before
    /// a quick one cannot land after it and take the well back.
    @MainActor private static var inFlight: Task<Void, Never>?

    /// Adopts a picture the caller already has as a `LibraryItem` — the menu button and the
    /// picker sheet's own selection, which both came from the index and so already know
    /// whether it carries a reference of its own.
    @MainActor
    static func adopt(_ item: LibraryItem, into store: GenerationStore) {
        begin(into: store) {
            if let source = item.referenceImage {
                return ReferenceImageEncoder.pngData(from: source)
            }
            return ReferenceImageEncoder.pngData(contentsOf: item.url)
        }
    }

    /// Adopts a picture named only by its id — a drop of a `LibraryItemReference`, which
    /// carries nothing else. `LibraryItem.ID` is the standardized file path, so this reads the
    /// file directly rather than asking a `LibraryIndex` to resolve it first, which is what
    /// lets the well accept the drop without holding an index of its own.
    @MainActor
    static func adopt(id: LibraryItem.ID, into store: GenerationStore) {
        let url = URL(fileURLWithPath: id)
        begin(into: store) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let reference = GenerationRecord.reference(in: data) {
                return ReferenceImageEncoder.pngData(from: reference)
            }
            return ReferenceImageEncoder.pngData(from: data)
        }
    }

    /// Runs `read` off the main actor and puts what it returns in the well, unless a newer
    /// choice has been made in the meantime.
    @MainActor
    private static func begin(
        into store: GenerationStore, _ read: @escaping @Sendable () -> Data?
    ) {
        inFlight?.cancel()
        inFlight = Task {
            let png = await Task.detached(priority: .userInitiated, operation: read).value
            guard !Task.isCancelled, let png else { return }
            store.useAsReference(png)
        }
    }
}
