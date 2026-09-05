import AppKit
import SwiftUI
import ZephraEngine

/// The grid's arrow keys: where the selection goes, and bringing it into view when it went
/// somewhere off screen.
///
/// Split from `LibraryGrid` so the grid draws and this decides. Shift held during an arrow
/// key means the selection grows from wherever it is anchored, the same rule a shift-click
/// follows. With nothing selected the first arrow selects an end of the grid — `LibraryCursor`
/// starts at the first image for right and down and the last for left and up — which is what
/// makes the keyboard's place in the grid visible without a focus ring round the whole pane.
///
/// The scroll is animated unless Reduce Motion is on. That is read from the workspace at the
/// moment of the key rather than held as a fourth stored property, which the three-property
/// rule leaves no room for beside the selection, the proxy and the index; the environment's
/// own `accessibilityReduceMotion` is the same reading.
struct LibraryGridKeyboard: ViewModifier {
    /// What is selected, shared with the pane that owns it.
    let selection: LibrarySelection
    /// The grid's scroll view, for revealing wherever the selection lands.
    let proxy: ScrollViewProxy

    @Environment(LibraryIndex.self) private var index

    func body(content: Content) -> some View {
        content.onMoveCommand { move($0) }
    }

    private func move(_ command: MoveCommandDirection) {
        guard let heading = LibraryCursor.Direction(command),
              let outcome = LibraryCursor.move(
                  heading,
                  in: index.sections,
                  columns: selection.columns,
                  selection: selection.ids,
                  anchor: selection.anchor,
                  extending: NSEvent.modifierFlags.contains(.shift)
              )
        else { return }
        selection.apply(outcome)
        guard let reveal = outcome.reveal else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            proxy.scrollTo(reveal, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(reveal, anchor: .center) }
        }
    }
}
