import AppKit
import Foundation
import UniformTypeIdentifiers
import ZephraCore
import ZephraEngine

/// Getting a finished image out of Zephra: onto disk, into the Finder, onto the clipboard.
enum ImageExport {
    /// A file name that carries the prompt's first words and the seed, so it stays findable.
    nonisolated static func suggestedFileName(for image: GeneratedImage) -> String {
        let words = image.settings.prompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "-")
            .lowercased()
        let stem = words.isEmpty ? "zephra" : words
        return "\(stem)-\(image.settings.seed).png"
    }

    /// The bytes to hand out. A picture that has a file is exported *as that file*, because
    /// the file is the truth: the upscale record and every annotation are written there and
    /// never into the bytes in memory. Before the save lands, the pixels with the generation
    /// record embedded, so a copy that leaves Zephra still says what made it; the plain pixels
    /// if the record cannot be embedded, and unchanged when one is already there.
    ///
    /// Not isolated to the main actor: drag-and-drop exports run off it.
    nonisolated static func exportData(for image: GeneratedImage) -> Data {
        if let url = image.fileURL, let onDisk = try? Data(contentsOf: url) { return onDisk }
        return (try? GenerationRecord.embedded(in: image)) ?? image.pngData
    }

    /// Asks where to put the image and writes it there: the file, once it has one, through
    /// the same path the library uses, so saving it onto itself is a no-op rather than a
    /// deletion; the bytes in memory until then.
    static func saveAs(_ image: GeneratedImage) {
        if let url = image.fileURL, exists(url) {
            saveAs(files: [url])
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFileName(for: image)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.exportData(for: image).write(to: url, options: .atomic)
        } catch {
            present(error, whileTryingTo: "save this image")
        }
    }

    /// Shows the image in the Finder, writing a temporary copy when it has no home yet.
    static func revealInFinder(_ image: GeneratedImage) {
        if let url = image.fileURL, exists(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard let temporary = writeTemporaryCopy(of: image) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([temporary])
    }

    /// Puts the image on the clipboard: its file, when it has one, so the Finder can paste the
    /// file and the bytes ride along; the PNG bytes alone until then.
    static func copyToPasteboard(_ image: GeneratedImage) {
        if let url = image.fileURL, exists(url) {
            copyToPasteboard(files: [url])
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(exportData(for: image), forType: .png)
    }

    /// A copy in the temporary directory, used for dragging out and for revealing unsaved images.
    ///
    /// Not isolated to the main actor: drag-and-drop exports run off it.
    nonisolated static func writeTemporaryCopy(of image: GeneratedImage) -> URL? {
        let url = URL.temporaryDirectory.appending(path: suggestedFileName(for: image))
        do {
            try Self.exportData(for: image).write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url
    }

    private static func present(_ error: Error, whileTryingTo action: String) {
        let alert = NSAlert()
        alert.messageText = "Zephra couldn't \(action)."
        alert.informativeText = "\(error.localizedDescription) Choose another folder and try again."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
