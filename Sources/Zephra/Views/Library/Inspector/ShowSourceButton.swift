import SwiftUI
import ZephraEngine

/// "Show Source": opens the picture a reference row's picture was made from, when the library
/// still has the file. Split out of `ReferenceFactsRow` so that row does not have to hold the
/// index and the viewer action just to draw one link.
struct ShowSourceButton: View {
    /// The library file name the reference picture came out of.
    let originName: String

    @Environment(LibraryIndex.self) private var index
    @Environment(\.viewLibraryItem) private var viewLibraryItem

    var body: some View {
        if let item = index.item(named: originName) {
            Button("Show Source") { viewLibraryItem(item) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}
