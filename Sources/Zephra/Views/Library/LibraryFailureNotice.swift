import SwiftUI
import ZephraEngine

/// Something the library could not do to a file, said once, quietly, over the grid.
///
/// The same shape as `SaveNotice` and for the same reason. The grid has already shown the
/// change optimistically and has already put it back from what is actually on disk, so nothing
/// is broken and nothing needs deciding — what is left is telling the person what the file
/// system said. It goes away by itself as soon as anything works.
struct LibraryFailureNotice: View {
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if let failure = index.lastFailure {
            NoticeCapsule(failure.message)
                .padding(.top, 10)
        }
    }
}
