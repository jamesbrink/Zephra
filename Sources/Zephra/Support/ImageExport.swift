import AppKit
import Foundation
import UniformTypeIdentifiers
import ZephraCore

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

    /// Asks where to put the image and writes the PNG bytes there.
    @discardableResult
    static func saveAs(_ image: GeneratedImage) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFileName(for: image)
        panel.canCreateDirectories = true
        panel.directoryURL = image.fileURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try image.pngData.write(to: url, options: .atomic)
            return url
        } catch {
            present(error, whileTryingTo: "save this image")
            return nil
        }
    }

    /// Shows the image in the Finder, writing a temporary copy when it has no home yet.
    static func revealInFinder(_ image: GeneratedImage) {
        if let url = image.fileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        guard let temporary = writeTemporaryCopy(of: image) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([temporary])
    }

    /// Puts the image on the clipboard as PNG bytes, ready to paste anywhere.
    static func copyToPasteboard(_ image: GeneratedImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(image.pngData, forType: .png)
    }

    /// A copy in the temporary directory, used for dragging out and for revealing unsaved images.
    ///
    /// Not isolated to the main actor: drag-and-drop exports run off it.
    nonisolated static func writeTemporaryCopy(of image: GeneratedImage) -> URL? {
        let url = URL.temporaryDirectory.appending(path: suggestedFileName(for: image))
        do {
            try image.pngData.write(to: url, options: .atomic)
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
