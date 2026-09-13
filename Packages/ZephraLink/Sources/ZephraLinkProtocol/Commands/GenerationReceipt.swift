import Foundation

/// Unknown is never permission to send the same press to another host.
public struct GenerationReceipt: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case prepared, accepted, completed, interrupted, unknown }
    public let requestID: UUID
    public let digest: String
    public let batchID: UUID?
    public var status: Status
    public var expectedCount: Int?
    public let recordedAt: Date
    public init(requestID: UUID, digest: String, batchID: UUID? = nil,
                status: Status, recordedAt: Date = Date()) {
        self.requestID = requestID; self.digest = digest; self.batchID = batchID
        self.status = status; self.recordedAt = recordedAt
    }
}
