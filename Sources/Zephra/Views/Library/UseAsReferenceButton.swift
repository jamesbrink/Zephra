import Foundation
import SwiftUI
import ZephraEngine

/// Puts a library image into the reference well beside the prompt.
///
/// An image that was itself edited from a picture hands back that picture, not itself: "use
/// this as a reference" on an edit almost always means "let me try that again from the same
/// starting point", and handing back the edit would compound one generation onto another.
///
/// The file is read and re-encoded off the main actor, through the same encoder the well uses,
/// so a large PNG is capped at 1024 pixels along its edge before anything holds it — the app
/// would otherwise carry the whole picture in memory, hash it, and write it into every image
/// the reference goes on to make.
struct UseAsReferenceButton: View {
    /// The image to start from.
    let item: LibraryItem

    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button { adopt() } label: {
            Text("Use as reference").frame(maxWidth: .infinity)
        }
        .disabled(!store.descriptor.capabilities.supportsReferenceImage)
    }

    private func adopt() {
        let item = item
        Task {
            let png = await Task.detached(priority: .userInitiated) { () -> Data? in
                if let source = item.referenceImage {
                    return ReferenceImageEncoder.pngData(from: source)
                }
                return ReferenceImageEncoder.pngData(contentsOf: item.url)
            }.value
            guard let png else { return }
            store.useAsReference(png)
        }
    }
}
