import Foundation
import ZephraCore
import ZephraMedia

/// The clip a bench run carried on, with the run joined onto its end.
enum BenchExtendedClip {
    /// Joins `media` onto `source` with its first `dropping` frames left out, writes the
    /// result beside `output` as `<stem>-extended.mp4`, and returns its path; nil when there
    /// was no clip to carry on or the run made a picture.
    static func write(_ media: GeneratedMedia, onto source: URL?, dropping: Int, beside output: URL)
        async throws -> String?
    {
        guard let source, case .video(let clip) = media else { return nil }
        let joined = try await MP4Stitcher().stitch([
            ClipPart(mp4: try Data(contentsOf: source)),
            ClipPart(mp4: clip.mp4, dropLeading: dropping),
        ])
        let stem = output.deletingPathExtension().lastPathComponent
        let url = output.deletingLastPathComponent().appendingPathComponent("\(stem)-extended.mp4")
        try joined.write(to: url, options: .atomic)
        return url.path
    }
}
