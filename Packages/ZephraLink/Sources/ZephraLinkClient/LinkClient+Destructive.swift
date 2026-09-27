import Foundation
import ZephraLinkProtocol

extension LinkClient {
    /// Unscoped destructive intent is safe only at the moment it was first requested.
    func destructiveRequest(_ command: Command) async throws -> Reply {
        var sent = false
        do {
            let reply = try await ask(command, onSent: { sent = true })
            switch reply {
            case .ok, .error: return reply
            default: throw LinkClientError.unexpectedReply
            }
        }
        catch is CancellationError { throw CancellationError() }
        catch {
            guard sent else { throw error }
            let action = command == .clearQueue ? "cleared the queue" : "stopped the work"
            throw LinkError(code: .busy, reason:
                "The Mac did not confirm this change. It may already have \(action). Check its current work before trying again.")
        }
    }

    /// Unlike `request`, this checks both refusals and unexpected replies.
    public func clearQueue() async throws {
        switch try await request(.clearQueue) {
        case .ok: return
        case .error(let error): throw error
        default: throw LinkClientError.unexpectedReply
        }
    }
}
