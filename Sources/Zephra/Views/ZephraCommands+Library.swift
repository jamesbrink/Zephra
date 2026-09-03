import Foundation
import SwiftUI
import ZephraCore
import ZephraEngine

/// Where Save as, Copy, Reveal and Delete actually land.
///
/// The four of them ask the same question and act on the same two answers, so the question is
/// asked once. The wording follows the answer too: "Delete Image" over one picture on the
/// canvas, "Delete 4 Images" over four in the grid, and "Delete 4 Images Immediately" inside
/// Recently Deleted, where it is the end of them.
extension ZephraCommands {
    /// What the file commands are about right now.
    enum Target {
        /// The image on the canvas, which may not have reached the disk yet.
        case canvas(GeneratedImage?)
        /// Images chosen in the library grid, which are files.
        case library([LibraryItem])

        /// Whether there is nothing to act on, which is what greys all four out.
        var isEmpty: Bool {
            switch self {
            case .canvas(let image): image == nil
            case .library(let items): items.isEmpty
            }
        }

        var saveTitle: String { count > 1 ? "Save \(count) Images as…" : "Save as…" }

        var copyTitle: String { count > 1 ? "Copy \(count) Images" : "Copy Image" }

        var deleteTitle: String { count > 1 ? "Delete \(count) Images" : "Delete Image" }

        private var count: Int {
            switch self {
            case .canvas: 1
            case .library(let items): items.count
            }
        }
    }

    /// The library's selection while the grid has the keyboard, and the canvas otherwise.
    var target: Target {
        guard let grid, let index = libraryIndex, !grid.ids.isEmpty else {
            return .canvas(store.current)
        }
        let chosen = index.sections.flatMap(\.items).filter { grid.contains($0.id) }
        return chosen.isEmpty ? .canvas(store.current) : .library(chosen)
    }

    func save() {
        switch target {
        case .canvas(let image): image.map { ImageExport.saveAs($0) }
        case .library(let items): ImageExport.saveAs(files: items.map(\.url))
        }
    }

    func copy() {
        switch target {
        case .canvas(let image): image.map { ImageExport.copyToPasteboard($0) }
        case .library(let items): ImageExport.copyToPasteboard(files: items.map(\.url))
        }
    }

    func reveal() {
        switch target {
        case .canvas(let image): image.map { ImageExport.revealInFinder($0) }
        case .library(let items): ImageExport.revealInFinder(files: items.map(\.url))
        }
    }

    /// On the canvas the file goes to the Trash, so nothing is asked: it is undoable in the
    /// Finder. In the library it goes to Recently Deleted, or, from inside that, for good —
    /// and that last one does ask. `LibraryIndex.delete(_:)` is the one place that decides.
    func delete() {
        switch target {
        case .canvas(let image): image.map { store.delete($0.id) }
        case .library(let items): libraryIndex?.delete(Set(items.map(\.id)))
        }
    }
}
