import Foundation
import ZephraCore
import ZephraLinkProtocol

extension LinkClient {
    public var supportsWorkflow: Bool { hasFreshSnapshot && snapshot?.workflow == true }
    public func workflow(_ command: WorkflowCommand) async throws -> Reply {
        guard supportsWorkflow else {
            throw LinkError(code: .unsupported, reason: "Update Zephra on this Mac to manage models and reorder its queue.")
        }
        let reply: Reply
        do { reply = try await request(.workflow(command)) }
        catch let error as LinkClientError where error.isWorthRepeating {
            switch command {
            case .download, .pause, .cancel:
                throw LinkError(code: .busy, reason: "The Mac did not confirm this change. Check its download status before trying again.")
            default: throw error
            }
        }
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
