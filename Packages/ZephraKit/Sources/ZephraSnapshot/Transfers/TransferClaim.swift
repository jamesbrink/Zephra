import Foundation
import ZephraCore

/// All writable repository dependencies, reserved together before any one is touched.
/// Different file sets serialize conservatively; identical variants share their source.
struct TransferClaim: Sendable {
    let parts: [RepositoryDownload]
    let root: URL

    init(_ model: ModelDescriptor, _ locations: ModelLocations) throws {
        root = locations.root
        var parts: [RepositoryDownload] = []
        if case .huggingFace(let repo, let revision, let patterns) = model.source {
            parts.append(RepositoryDownload(repoID: repo, revision: revision,
                patterns: patterns.sorted(), destination: locations.downloads(repoID: repo)))
        }
        // The variant's own directory is claimed too when a mirror publishes it, so two
        // requests for one model share the one fetch and nothing else writes there meanwhile.
        if let prebuilt = RepositoryDownload.prebuilt(model, in: locations) { parts.append(prebuilt) }
        for group in Dictionary(grouping: parts, by: { Self.path($0.destination) }).values {
            guard Set(group.map(\.revision)).count == 1, Set(group.map(\.repoID)).count == 1 else {
                throw BackendError.downloadFailed("One model requests incompatible revisions in the same folder.")
            }
        }
        self.parts = Self.grouped(parts)
    }

    static func grouped(_ parts: [RepositoryDownload]) -> [RepositoryDownload] {
        Dictionary(grouping: parts, by: { path($0.destination) }).values.map { group in
            let first = group[0]
            return RepositoryDownload(repoID: first.repoID, revision: first.revision,
                patterns: Array(Set(group.flatMap(\.patterns))).sorted(), destination: first.destination,
                origin: first.origin)
        }.sorted { path($0.destination) < path($1.destination) }
    }

    func conflicts(with other: TransferClaim) -> Bool {
        parts.contains { part in
            other.parts.contains { Self.path($0.destination) == Self.path(part.destination) && $0 != part }
        }
    }

    static func path(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
