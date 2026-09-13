import SwiftUI
import ZephraCore

/// The canvas's half of `ReferenceIntent`: the name the library asked to start from, turned
/// into the picture in the well.
///
/// A modifier rather than a view, because there is nothing to draw — it is the canvas listening.
/// The canvas is where it goes because the canvas owns the capsule, and because a request made
/// while the library was up is still here when the tab changes: the intent holds it until
/// somebody takes it, which is the whole reason it is an object rather than a notification.
///
/// What to do with the bytes rides in as a closure, the way every door into the Mac's own
/// reference well hands `adoptReference` one. The capabilities that decide whether the size
/// follows the picture live on the snapshot, and the caller already has it.
struct ReferenceIntentReader: ViewModifier {
    /// What the bytes become: the well filled, at the model's own size rule, naming the file
    /// they came from.
    let fill: (ReferencePicture, String) -> Bool

    @Environment(ReferenceIntent.self) private var intent
    @Environment(LibraryCatalog.self) private var catalog

    func body(content: Content) -> some View {
        content
            // `onChange` and an unstructured task rather than `.task(id:)`: taking the request
            // clears the name, and a task keyed on the name would cancel itself mid-fetch.
            // `initial` covers a request made before this surface was ever built.
            .onChange(of: intent.fileName, initial: true) { _, name in
                guard name != nil else { return }
                Task { await ReferenceAdoption.take(intent, from: catalog, fill: fill) }
            }
    }
}
