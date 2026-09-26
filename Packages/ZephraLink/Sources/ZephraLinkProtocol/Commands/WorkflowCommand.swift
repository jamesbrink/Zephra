import Foundation

/// Optional companion workflows; expanded data is sent only in response to these requests.
public enum WorkflowCommand: Codable, Hashable, Sendable {
    case history
    case storage
    case reorder(id: UUID, batches: [UUID], entries: [UUID])
    case download(String)
    case pause(String)
    case cancel(String)
    case delete(id: UUID, token: UUID)
}
