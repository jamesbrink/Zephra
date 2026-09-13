import Foundation
import ZephraLinkProtocol

nonisolated struct Submission: Codable, Identifiable, Sendable {
    enum State: String, Codable { case sending, accepted, completed, interrupted, rejected, unknown }
    let generation: StrictGeneration
    let hostID: HostID
    let hostName: String
    var state: State
    var batchID: UUID?
    var note: String?
    let createdAt: Date
    var id: UUID { generation.request.requestID }
}
