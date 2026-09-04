import Foundation
import ZephraCore

/// What becomes of the bytes an upscale hands back: the picture on the canvas, the record it
/// carries, and the file it is written to.
extension GenerationStore {
    /// Publishes the larger picture straight away and only then starts writing it, so the canvas
    /// never waits on the file system — the same order a finished generation follows.
    ///
    /// It reaches the canvas only when the canvas was showing the picture it was made from, or
    /// was showing nothing at all. An upscale started from the library grid, of some picture
    /// other than the one on the canvas, lands in history and in the library without moving what
    /// the user is looking at — the rule a finished generation follows through `followsRun`.
    func completeUpscale(
        _ data: Data, parent: UpscaleParent, factor: Int, duration: Duration
    ) {
        let record = GenerationRecord.upscaled(
            from: parent.record,
            parentFileName: parent.fileName,
            factor: factor,
            size: Self.size(of: data, parent: parent, factor: factor),
            duration: duration)
        let image = GeneratedImage(
            pngData: data,
            settings: record.settings(),
            modelID: record.modelID,
            createdAt: record.createdAt,
            duration: duration)
        if current == nil || current?.fileURL == parent.url { current = image }
        history.insert(image, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastLibraryFailure = nil
        writeUpscale(data, record: record, parent: parent, factor: factor, imageID: image.id)
    }

    /// How large the result actually is: its own header first, because an upscaler trims its
    /// input to a multiple of its stride and the edges are not always the parent's times the
    /// factor. The parent's own header times the factor is the fallback, and it is only ever
    /// reached by bytes that are not a PNG, which the write would fail on anyway.
    private static func size(of data: Data, parent: UpscaleParent, factor: Int) -> ImageSize {
        if let read = PNGImageSize.read(from: data) { return read }
        guard let source = PNGImageSize.read(from: parent.pngData) else {
            return ImageSize(width: 0, height: 0)
        }
        return ImageSize(width: source.width * factor, height: source.height * factor)
    }

    /// Writes the result into the library root under `<parent stem>-x<factor>.png`.
    ///
    /// The root rather than literally beside the parent: an imported picture lives in the
    /// library's own `Sources` folder, where a scan skips anything carrying a generation record,
    /// so a result written there would be invisible. For every generated parent the root *is*
    /// beside it.
    private func writeUpscale(
        _ data: Data, record: GenerationRecord, parent: UpscaleParent, factor: Int,
        imageID: GeneratedImage.ID
    ) {
        let library = library
        let name = "\(parent.url.deletingPathExtension().lastPathComponent)-x\(factor).png"
        let referenceText = parent.referenceText
        saveTask = Task.detached(priority: .utility) {
            do {
                let url = try library.write(
                    data, record: record, named: name, referenceText: referenceText)
                await MainActor.run { self.attach(url, to: imageID) }
            } catch {
                let failure = SaveFailure(imageID: imageID, reason: error.readableMessage)
                await MainActor.run { self.saveFailed(failure) }
            }
        }
    }
}
