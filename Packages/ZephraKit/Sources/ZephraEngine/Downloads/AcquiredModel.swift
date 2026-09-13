import Foundation
import ZephraCore

/// Validated files with an acquisition lease held until inference unloads them.
struct AcquiredModel: Sendable {
    var installedOnly = false
    let id: UUID
    let model: ModelDescriptor
    let locations: ModelLocations
    let directory: URL
}
