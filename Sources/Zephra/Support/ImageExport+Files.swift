import AppKit
import Foundation
import UniformTypeIdentifiers

/// Getting images out of the library, where what there is to hand out is a file rather than a
/// picture in memory.
///
/// Copying the file rather than re-encoding it is the whole point: the PNG on disk already
/// carries its generation record and whatever has been said about it, and reading it back only
/// to write it out again would be slower and could only lose something.
///
/// Every copy goes through an `ExportPlan` first, so a file is never copied onto itself — the
/// one way an export could destroy what it was exporting — and a batch that would overwrite
/// asks before it does.
extension ImageExport {
    /// Asks where to put one image, or which folder to put several in, and copies them there.
    static func saveAs(files: [URL]) {
        guard let first = files.first else { return }
        guard files.count > 1 else {
            saveOne(first)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save \(files.count) Images"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        export(files, into: folder)
    }

    /// Puts the images on the clipboard: the pixels of a single one, so it can be pasted into
    /// anything, and the file references either way, so the Finder can paste them as files.
    static func copyToPasteboard(files: [URL]) {
        guard !files.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0 as NSURL })
        guard files.count == 1, let data = try? Data(contentsOf: files[0]) else { return }
        pasteboard.setData(data, forType: .png)
    }

    /// Shows the images in the Finder, selected.
    static func revealInFinder(files: [URL]) {
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    /// Copies `files` into `folder` under their own names, asking what to do about any that
    /// are already there under another file, and leaving alone any that *are* the file there.
    static func export(_ files: [URL], into folder: URL) {
        var plan = ExportPlan.make(files: files, into: folder, exists: exists, isSameFile: isSameFile)
        if !plan.collisions.isEmpty {
            switch ExportCollisionPrompt.ask(about: plan, in: folder) {
            case .keepBoth: plan = plan.keepingBoth(exists: exists)
            case .replace: plan = plan.replacing()
            case .cancel: return
            }
        }
        perform(plan)
    }

    /// One image through the save panel, which has already asked about overwriting; saving a
    /// file onto itself is nothing to do rather than something to refuse.
    private static func saveOne(_ file: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = file.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let copy = ExportPlan.Copy(source: file, destination: destination)
        perform(ExportPlan.make(copies: [copy], exists: exists, isSameFile: isSameFile).replacing())
    }

    /// Runs the copies, and reports every failure in one alert rather than one each.
    private static func perform(_ plan: ExportPlan) {
        var failed: [String] = []
        var firstError: Error?
        for copy in plan.copies {
            do {
                try copyReplacing(copy.source, to: copy.destination)
            } catch {
                failed.append(copy.source.lastPathComponent)
                firstError = firstError ?? error
            }
        }
        guard let firstError else { return }
        let alert = NSAlert()
        let named = failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? ", …" : "")
        alert.messageText = failed.count == 1
            ? "Zephra couldn't save \(named)."
            : "Zephra couldn't save \(failed.count) images: \(named)."
        alert.informativeText = "\(firstError.localizedDescription) Choose another folder and try again."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
