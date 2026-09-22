import SwiftUI
import ZephraCore

/// The canvas's half of `ReferenceIntent`: the names the library asked to start from, turned
/// into the pictures in the well.
///
/// A modifier rather than a view, because there is nothing to draw — it is the canvas listening.
/// The canvas is where it goes because the canvas owns the capsule, and because a request made
/// while the library was up is still here when the tab changes: the intent holds it until
/// somebody takes it, which is the whole reason it is an object rather than a notification.
///
/// What to do with the pictures rides in as a closure, the way every door into the Mac's own
/// reference well hands `adoptReferences` one. They arrive as one batch, in the order they were
/// named, so the draft decides once how many of them there is room for.
struct ReferenceIntentReader: ViewModifier {
    /// What the pictures become: the well filled, at the model's own size rule, each naming the
    /// file it came from.
    let fill: ([ReferencePicture]) -> Bool

    @Environment(ReferenceIntent.self) private var intent
    @Environment(LibraryCatalog.self) private var catalog

    func body(content: Content) -> some View {
        content
            // `onChange` and an unstructured task rather than `.task(id:)`: taking the request
            // clears the names, and a task keyed on them would cancel itself mid-fetch.
            // `initial` covers a request made before this surface was ever built.
            .onChange(of: intent.fileNames, initial: true) { _, names in
                guard !names.isEmpty else { return }
                Task { await ReferenceAdoption.take(intent, from: catalog, fill: fill) }
            }
    }
}
