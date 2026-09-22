import Foundation

/// The picture an upscale starts from, read off the disk in one pass.
///
/// The reference chunk is kept as the base64 **text** it was written as, never decoded: the
/// result copies it through verbatim, so `referenceBytes` in the record it inherits still counts
/// what the chunk actually carries.
struct UpscaleParent: Sendable {
    /// Where the picture lives.
    let url: URL
    /// Its bytes, which are what the upscaler is handed.
    let pngData: Data
    /// What made it, or nil for an imported photograph or a PNG some other tool wrote.
    let record: GenerationRecord?
    /// Its numbered `zephra:reference` chunks, verbatim and in order, empty when it carries
    /// none. Every one of them, so an upscale of a several-picture edit keeps every picture.
    let referenceTexts: [String]

    /// The file's name, which is what the result's record records it by.
    var fileName: String { url.lastPathComponent }

    /// Reads one picture and everything the upscale needs to know about it, off the main actor.
    /// Nil when the file has gone or is not a PNG at all.
    static func read(_ url: URL) async -> UpscaleParent? {
        await Task.detached(priority: .userInitiated) { () -> UpscaleParent? in
            guard let data = try? Data(contentsOf: url),
                  let text = try? PNGTextChunks.read(from: data)
            else { return nil }
            return UpscaleParent(
                url: url,
                pngData: data,
                record: GenerationRecord.decode(from: text),
                referenceTexts: GenerationRecord.referenceTexts(in: text))
        }.value
    }
}
