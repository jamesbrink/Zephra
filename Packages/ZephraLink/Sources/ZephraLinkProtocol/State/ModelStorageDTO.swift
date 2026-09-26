import Foundation

/// A Mac-issued deletion token, never a caller-supplied filesystem path.
public struct ModelStorageDTO: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let detail: String
    public let modelIDs: [String]
    public let bytes: Int64?
    public let inUse: Bool
    public init(id: UUID, name: String, detail: String, modelIDs: [String], bytes: Int64?, inUse: Bool) {
        self.id = id; self.name = name; self.detail = detail
        self.modelIDs = modelIDs; self.bytes = bytes; self.inUse = inUse
    }
}
