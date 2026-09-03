import SwiftUI
import ZephraEngine

/// An image the canvas was asked to show and could not, said over the capsule.
///
/// It is nearly always a file that has moved or gone since the library last looked at it — the
/// grid is a picture of the folder as it was a moment ago, and a folder can be changed by
/// anything. The canvas keeps whatever it was already showing, so there is nothing to put back
/// and nothing to decide; the next thing that opens clears it.
struct OpenFailureNotice: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if let failure = store.lastLibraryFailure {
            NoticeCapsule(failure.message)
        }
    }
}
