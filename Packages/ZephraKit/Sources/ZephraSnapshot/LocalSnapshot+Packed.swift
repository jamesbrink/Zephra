import Foundation
import ZephraCore

extension LocalSnapshot {
    /// Where `descriptor`'s packed variant is on this Mac, or nil when it has not been built.
    ///
    /// Every root the models folder has been is looked at, the current one first: a variant
    /// packed under a folder the setting has since moved away from is still the same
    /// gigabytes, and building it again — or fetching its release again — because a setting
    /// moved is exactly what `ModelLocations.previous` exists to prevent. A new build still
    /// goes to `locations.built(descriptor)`, under the current root.
    public func packedVariant(
        of descriptor: ModelDescriptor, in locations: ModelLocations
    ) -> URL? {
        locations.builtCandidates(for: descriptor).first { missingEntry(in: $0) == nil }
    }
}
