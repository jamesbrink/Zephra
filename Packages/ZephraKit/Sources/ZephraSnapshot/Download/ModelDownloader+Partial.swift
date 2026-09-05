import Foundation
import ZephraCore

/// What becomes of an `.incomplete` file: put in place once it is whole, or thrown away when
/// the server would not resume it.
extension ModelDownloader {
    /// Puts the finished file in place, over whatever was there.
    func replace(_ partial: URL, with target: URL) throws {
        let files = FileManager.default
        try? files.removeItem(at: Self.validator(of: partial))
        if files.fileExists(atPath: target.path(percentEncoded: false)) {
            try files.removeItem(at: target)
        }
        try files.moveItem(at: partial, to: target)
    }

    /// Removes a partial the transfer cannot continue from. A failure here is an error of its
    /// own rather than something to shrug at: a partial left behind is appended onto at the
    /// next attempt, and the size check then catches the splice as a misleading "ended early".
    static func discardPartial(_ partial: URL, of file: RepositoryFile) throws {
        guard FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: partial)
        } catch {
            throw ModelDownloadError.interrupted(
                reason: "Couldn't discard the partial \(file.path): \(error.localizedDescription)")
        }
    }
}
