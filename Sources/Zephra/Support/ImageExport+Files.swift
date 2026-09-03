import AppKit
import Foundation
import UniformTypeIdentifiers

/// Getting images out of the library, where what there is to hand out is a file rather than a
/// picture in memory.
///
/// Copying the file rather than re-encoding it is the whole point: the PNG on disk already
/// carries its generation record and whatever has been said about it, and reading it back only
/// to write it out again would be slower and could only lose something.
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
        for file in files { copy(file, into: folder) }
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

    private static func saveOne(_ file: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = file.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        write(file, to: destination)
    }

    private static func copy(_ file: URL, into folder: URL) {
        write(file, to: folder.appending(path: file.lastPathComponent))
    }

    /// Copies one file, replacing whatever is at the destination — the save panel has already
    /// asked about that, and the folder panel is the user naming a folder they own.
    private static func write(_ file: URL, to destination: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Zephra couldn't save \(file.lastPathComponent)."
            alert.informativeText = "\(error.localizedDescription) Choose another folder and try again."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
