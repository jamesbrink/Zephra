import Foundation
import ZephraCore
import ZephraLinkProtocol

extension LinkClient {
    public var supportsWorkflow: Bool { hasFreshSnapshot && snapshot?.workflow == true }
    public func workflow(_ command: WorkflowCommand) async throws -> Reply {
        guard supportsWorkflow else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to manage models and reorder its queue.")
        }
        let reply = try await request(.workflow(command))
        if case .error(let error) = reply { throw error }
        return reply
    }
    public func promptHistory() async throws -> [PromptHistoryEntry] {
        guard case .workflow(.history(let entries)) = try await workflow(.history) else {
            throw LinkClientError.unexpectedReply
        }
        return entries
    }
    public func modelStorage() async throws -> [ModelStorageDTO] {
        guard case .workflow(.storage(let rows)) = try await workflow(.storage) else {
            throw LinkClientError.unexpectedReply
        }
        return rows
    }
}
