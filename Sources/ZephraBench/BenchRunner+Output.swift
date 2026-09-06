import Foundation
import ZephraCore

/// Where a run's result goes, and the arithmetic of the report.
extension BenchRunner {
    /// Writes the run's result and answers where. A picture goes to `url` as it is; a clip
    /// goes to `url` with an `.mp4` extension, with its first frame as a PNG beside it, so
    /// the poster can be looked at without a player and the path in the report is the clip.
    static func write(_ media: GeneratedMedia, to url: URL) throws -> String {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch media {
        case .image(let png):
            try png.write(to: url)
            return url.path
        case .video(let video):
            let clip = url.deletingPathExtension().appendingPathExtension("mp4")
            try video.mp4.write(to: clip)
            try video.poster.write(to: url.deletingPathExtension().appendingPathExtension("png"))
            return clip.path
        }
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    static func note(_ message: String, _ verbose: Bool) {
        guard verbose else { return }
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
