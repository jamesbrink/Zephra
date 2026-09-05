import Foundation

/// Revision provenance for flat downloads. Unmarked legacy files are trusted only for main.
enum RepositoryRevision {
    static func matches(_ directory: URL, revision: String) -> Bool {
        let requested = directory.appending(path: ".zephra-requested-revision")
        let commit = directory.appending(path: ".zephra-commit")
        if let recorded = try? String(contentsOf: requested, encoding: .utf8) {
            if recorded == revision { return true }
            return (try? String(contentsOf: commit, encoding: .utf8)) == revision
        }
        return revision == "main" || (try? String(contentsOf: commit, encoding: .utf8)) == revision
    }
}
