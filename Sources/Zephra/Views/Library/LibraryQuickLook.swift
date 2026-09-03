import QuickLook
import SwiftUI
import ZephraEngine

/// Space shows the selected image full size, and space again puts it away.
///
/// The Finder's gesture, and the reason the grid can afford small thumbnails: judging a picture
/// properly is one keystroke rather than a change of pane. The whole selection goes to Quick
/// Look, so its own arrow keys walk the images that were chosen.
struct LibraryQuickLook: ViewModifier {
    /// What is selected in the grid.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index
    @State private var showing: URL?

    func body(content: Content) -> some View {
        content
            .quickLookPreview($showing, in: urls)
            .onKeyPress(.space) {
                guard showing == nil else {
                    showing = nil
                    return .handled
                }
                guard let first = urls.first else { return .ignored }
                showing = first
                return .handled
            }
            .onChange(of: selection.ids) { if showing != nil { showing = urls.first } }
    }

    /// The selected images as files, in the order the grid is showing them, so Quick Look's own
    /// arrows walk them the way the eye does.
    private var urls: [URL] {
        index.sections
            .flatMap(\.items)
            .filter { selection.contains($0.id) }
            .map(\.url)
    }
}
