import Foundation
import ZephraCore
import ZephraEngine

/// The window a frozen build opens on: where it is looking, the library it shows and the run
/// its queue holds. Stated rather than restored, so a screenshot is the same on every machine.
extension InterfacePreview {
    /// Where the frozen window is looking. Stated rather than restored, so a screenshot build
    /// shows the same thing on every machine.
    static func workspace() -> WorkspaceSelection? {
        guard requestedState != nil else { return nil }
        let workspace = WorkspaceSelection(pane: name == "library" || name == "viewer" ? .library : .canvas)
        // `tucked` exists to photograph the lip, so the window has to actually be tucked when
        // the screenshot is taken rather than reaching that state through a simulated click.
        if name == "tucked" { workspace.promptTucked = true }
        // `models` exists to photograph the browser, so the sheet is up when the screenshot is
        // taken rather than reached through a simulated click, the way `tucked` is tucked.
        if name == "models" { workspace.showsModelBrowser = true }
        // `picker` photographs the reference sheet, which is the browser's rival for the one
        // sheet a window has, so it is stated here beside it rather than reached through an
        // `onAppear` hook inside the well.
        if wantsReferencePicker { workspace.showsReferencePicker = true }
        return workspace
    }

    /// The one item the frozen `viewer` window shows full size, or nil otherwise.
    ///
    /// `workspace()` cannot answer this itself: it and `index()` are called independently and
    /// each builds its own `LibraryIndex.preview`, over its own temporary files, so only the
    /// index that actually ends up in the window knows which id its first item got. The
    /// composition root calls this once both exist, after `index.start()`.
    static func viewing(in index: LibraryIndex) -> LibraryItem.ID? {
        guard requestedState != nil, name == "viewer" else { return nil }
        return index.sections.first?.items.first?.id
    }

    /// A library with no folder behind it, or nil for a normal launch. Nothing in it is read
    /// from or written to a disk, so a frozen window shows a full grid on a machine that has
    /// never generated anything.
    static func index() -> LibraryIndex? {
        guard requestedState != nil else { return nil }
        if name == "settings" { return LibraryIndex(library: AppSettings.imageLibrary()) }
        // Real files in the temporary directory, so the grid shows pictures. The index itself
        // still touches no disk: it is handed the paths and never looks for a folder.
        return LibraryIndex.preview(count: 38, pictures: PreviewImages.libraryFiles(count: 41))
    }

    /// A run of `count` seeds of one prompt, the first of which is the one being rendered.
    /// Shared with the `#Preview`s of the queue, so the frozen window and the previews of its
    /// parts are showing the same thing.
    static func queuedRun(of count: Int = 3, steps: Int = 4, frames: Int = 1) -> [QueuedGeneration] {
        let batch = UUID()
        let settings = GenerationSettings(
            prompt: "a red bicycle against a limestone wall",
            size: ImageSize(width: 1024, height: 1024),
            steps: steps,
            guidance: 0,
            seed: 8_123_447_209_115_662,
            frames: frames
        )
        return (0..<count).map { index in
            var seeded = settings
            seeded.seed &+= UInt64(index)
            return QueuedGeneration(
                model: ModelCatalog.default,
                settings: seeded,
                batchID: batch,
                batchIndex: index
            )
        }
    }
}
