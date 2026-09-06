import Foundation
import SwiftUI
import ZephraCore
import ZephraEngine

/// Where Export, Share, Copy, Reveal, Delete, Use as Reference and Upscale actually land.
///
/// All of them ask the same question and act on the same answers, so the question is asked
/// once, in `CommandTarget`. The wording follows the answer too: "Delete Image" over one
/// picture on the canvas, "Delete 4 Images" over four in the grid.
extension ZephraCommands {
    /// What the file commands are about right now: the canvas's picture while the canvas pane
    /// is showing one, the grid's selection while the grid has the keyboard, and otherwise
    /// nothing. Never the canvas's picture from behind the library.
    var target: CommandTarget {
        CommandTarget.resolve(
            pane: workspace.pane,
            isShowingRun: store.isShowingRun,
            current: store.current,
            gridSelection: grid?.ids,
            sections: libraryIndex?.sections ?? [])
    }

    /// The picture the two Upscale items act on: the one image chosen in the grid, or the one on
    /// the canvas.
    ///
    /// Nil for several images, because an upscale is one picture at a time, and nil inside
    /// Recently Deleted, where the remedies are Put Back and Delete Immediately and making a
    /// larger copy of something on its way out would be the wrong offer entirely.
    var upscaleSource: UpscaleSource? {
        switch target {
        case .none:
            return nil
        case .canvas(let image):
            // A clip's poster is not a picture to make larger.
            return image.isVideo ? nil : .image(image)
        case .library:
            guard let item = target.singleItem, !item.isVideo,
                libraryIndex?.query.scope != .recentlyDeleted
            else { return nil }
            return .file(item.url)
        }
    }

    /// Whether Use as Reference has one picture to take and a model that reads one.
    var canUseAsReference: Bool {
        guard store.descriptor.capabilities.supportsReferenceImage else { return false }
        switch target {
        case .none: return false
        case .canvas: return true
        case .library: return target.singleItem != nil
        }
    }

    /// Puts the one picture the commands are about into the reference well, the way the
    /// inspector's own button does — a library picture also brings the canvas up, since that
    /// is where the well is.
    func useAsReference() {
        switch target {
        case .none:
            return
        case .canvas(let image):
            ReferenceAdoption.adopt(image, into: store)
        case .library:
            guard let item = target.singleItem else { return }
            ReferenceAdoption.adopt(item, into: store)
            workspace.pane = .canvas
        }
    }

    /// Makes that picture `factor` times larger. Does nothing when there is none, which is also
    /// what greys the items.
    func upscale(_ factor: Int) {
        guard let upscaleSource else { return }
        store.upscale(upscaleSource, factor: factor)
    }

    func save() {
        switch target {
        case .none: return
        case .canvas(let image): ImageExport.saveAs(image)
        case .library(let items): ImageExport.saveAs(files: items.exportURLs)
        }
    }

    /// The files Share… would hand the picker: a canvas picture only once it has one, since the
    /// sharing services take files and a picture still being written has none to give.
    var shareFiles: [URL] {
        switch target {
        case .none: return []
        case .canvas(let image): return image.fileURL.map { [$0] } ?? []
        case .library(let items): return items.exportURLs
        }
    }

    func share() { SharePicker.show(files: shareFiles) }

    func copy() {
        switch target {
        case .none: return
        case .canvas(let image): ImageExport.copyToPasteboard(image)
        case .library(let items): ImageExport.copyToPasteboard(files: items.exportURLs)
        }
    }

    func reveal() {
        switch target {
        case .none: return
        case .canvas(let image): ImageExport.revealInFinder(image)
        case .library(let items): ImageExport.revealInFinder(files: items.exportURLs)
        }
    }

    /// Both ways go to Recently Deleted, so nothing is asked — except from inside Recently
    /// Deleted, where `LibraryIndex.delete(_:)` is the end of them and does ask.
    func delete() {
        switch target {
        case .none: return
        case .canvas(let image): store.delete(image.id)
        case .library(let items): libraryIndex?.delete(Set(items.map(\.id)))
        }
    }
}
