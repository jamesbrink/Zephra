import Foundation
import Observation

/// "Use these pictures as the references", said by the library and heard by the capsule.
///
/// One `@Observable` with one fact on it, injected by the composition root, rather than a
/// notification. Three reasons. A notification is a fact with no owner, and the phone's rule is
/// that a view reads what it draws from an object it was handed. A notification posted while
/// the canvas is not built reaches nobody, whereas this is still here when the tab is switched
/// to. And a name on an observable object is a thing a test can set and read.
///
/// It carries library **file names**, never the bytes. The Mac already has the pictures; what
/// the phone is asking for is that the next generation start from the files it names, which is
/// what `ReferencePicture.origin` is on the Mac. Fetching a PNG to send it back to the machine
/// it came from would be megabytes over a relay to say a word.
///
/// Several names and one request, because a door that hands over five pictures is one choice:
/// five requests under five revisions would land only the last, which is exactly what the
/// revision exists to prevent.
///
/// **The canvas owns the other half.** `ReferenceIntentReader` takes the names, fetches each
/// picture through `LibraryCatalog` — the one cache both surfaces read whole pictures out of —
/// and fills the well with all of them at once. Nothing else may take them: two readers and the
/// second gets nothing.
@MainActor
@Observable
final class ReferenceIntent {
    /// The pictures the library asked to start from, in the order they were chosen, or empty
    /// once the capsule has taken them.
    private(set) var fileNames: [String] = []
    private(set) var revision = UUID()
    private(set) var isResolving = false
    private(set) var note: String?
    var canGenerate: Bool { fileNames.isEmpty && !isResolving && note == nil }

    /// The first name asked for, which is what a single-picture reader means.
    var fileName: String? { fileNames.first }

    /// An intent with nothing in it.
    init() {}

    /// Asks for the next generation to start from this picture.
    func use(_ fileName: String) { use([fileName]) }

    /// Asks for the next generation to start from these pictures, in this order.
    func use(_ fileNames: [String]) {
        beginSelection()
        self.fileNames = fileNames
    }

    func beginSelection() {
        revision = UUID()
        fileNames = []
        isResolving = true
        note = "Loading reference…"
    }

    /// Takes the request, leaving nothing behind. The capsule's call, and the reason this is
    /// not a plain property: a request acted on twice would refill a well somebody emptied.
    func take() -> [String] {
        defer { fileNames = [] }
        return fileNames
    }

    /// Drops the request without acting on it.
    func clear() {
        revision = UUID()
        isResolving = false
        note = nil
        fileNames = []
    }

    func resolved(_ revision: UUID, success: Bool) {
        guard self.revision == revision else { return }
        isResolving = false
        note = success ? nil : "The reference could not be loaded. Reconnect its Mac or choose another picture."
    }
}
