import Foundation
import Observation

/// "Use this picture as the reference", said by the library and heard by the capsule.
///
/// One `@Observable` with one fact on it, injected by the composition root, rather than a
/// notification. Three reasons. A notification is a fact with no owner, and the phone's rule is
/// that a view reads what it draws from an object it was handed. A notification posted while
/// the canvas is not built reaches nobody, whereas this is still here when the tab is switched
/// to. And a name on an observable object is a thing a test can set and read.
///
/// It carries the library **file name**, never the bytes. The Mac already has the picture; what
/// the phone is asking for is that the next generation start from the file it names, which is
/// what `GenerationSettings.referenceOrigin` is on the Mac. Fetching the PNG to send it back to
/// the machine it came from would be megabytes over a relay to say a word.
///
/// **The canvas owns the other half.** `ReferenceIntentReader` takes the name, fetches the
/// picture through `LibraryCatalog` — the one cache both surfaces read whole pictures out of —
/// and fills the well. Nothing else may take it: two readers and the second gets nothing.
@MainActor
@Observable
final class ReferenceIntent {
    /// The picture the library asked to start from, or nil once the capsule has taken it.
    private(set) var fileName: String?
    private(set) var revision = UUID()
    private(set) var isResolving = false
    private(set) var note: String?
    var canGenerate: Bool { fileName == nil && !isResolving && note == nil }

    /// An intent with nothing in it.
    init() {}

    /// Asks for the next generation to start from this picture.
    func use(_ fileName: String) {
        beginSelection()
        self.fileName = fileName
    }

    func beginSelection() {
        revision = UUID()
        fileName = nil
        isResolving = true
        note = "Loading reference…"
    }

    /// Takes the request, leaving nothing behind. The capsule's call, and the reason this is
    /// not a plain property: a request acted on twice would refill a well somebody emptied.
    func take() -> String? {
        defer { fileName = nil }
        return fileName
    }

    /// Drops the request without acting on it.
    func clear() {
        revision = UUID()
        isResolving = false
        note = nil
        fileName = nil
    }
    func resolved(_ revision: UUID, success: Bool) {
        guard self.revision == revision else { return }
        isResolving = false
        note = success ? nil : "The reference could not be loaded. Reconnect its Mac or choose another picture."
    }

}
