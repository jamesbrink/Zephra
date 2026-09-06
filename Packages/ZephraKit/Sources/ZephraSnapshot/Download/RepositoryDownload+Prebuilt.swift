import Foundation
import ZephraCore

extension RepositoryDownload {
    /// The packed variant of `descriptor` from its mirror, landing in the `.partial` sibling of
    /// `locations.built(descriptor)` — the same directory a build writes into before it is
    /// renamed into place, so nothing reads a variant with files still to come as a model.
    /// Nil for a descriptor that has no mirror or is not built locally.
    static func prebuilt(_ descriptor: ModelDescriptor, in locations: ModelLocations)
        -> RepositoryDownload?
    {
        guard descriptor.isPublishedPrebuilt, let mirror = descriptor.mirror else { return nil }
        return RepositoryDownload(
            repoID: descriptor.id, revision: "prebuilt", patterns: [],
            destination: ModelDownloader.prebuiltPartial(of: descriptor, in: locations),
            origin: .mirror(mirror, identity: PackedProvenance.identity(descriptor)))
    }
}
