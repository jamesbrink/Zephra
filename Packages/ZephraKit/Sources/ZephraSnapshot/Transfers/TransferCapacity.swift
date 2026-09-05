import Foundation

/// A volume's shared free-space budget; injectable for full-disk tests.
public struct TransferCapacity: Sendable {
    public let id: String
    public let available: Int64?

    public init(id: String, available: Int64?) { self.id = id; self.available = available }

    public static func read(_ url: URL) throws -> Self {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        let values = try existing.resourceValues(forKeys: [.volumeIdentifierKey, .volumeAvailableCapacityForImportantUsageKey])
        return Self(id: String(describing: values.volumeIdentifier), available: values.volumeAvailableCapacityForImportantUsage)
    }
}
