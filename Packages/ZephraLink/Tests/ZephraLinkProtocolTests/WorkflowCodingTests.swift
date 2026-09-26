import Foundation
import Testing
import ZephraCore
@testable import ZephraLinkProtocol

@Suite("Optional workflow wire compatibility")
struct WorkflowCodingTests {
    @Test func everyWorkflowRoundTrips() throws {
        let id = UUID()
        let commands: [WorkflowCommand] = [.history, .storage, .reorder(id: id, batches: [id], entries: [id]),
            .download("a"), .pause("a"), .cancel("a"), .delete(id: id, token: id)]
        for command in commands { #expect(try LinkFixtures.roundTrip(Command.workflow(command)) == .workflow(command)) }
        let replies: [WorkflowReply] = [.history([PromptHistoryEntry(id: id, prompt: "long\ntext")]),
            .storage([ModelStorageDTO(id: id, name: "Model", detail: "Shared", modelIDs: ["a", "b"], bytes: 1024, inUse: true)])]
        for reply in replies { #expect(try LinkFixtures.roundTrip(Reply.workflow(reply)) == .workflow(reply)) }
    }
    @Test func legacySnapshotOmitsFlag() throws {
        let data = try LinkJSON.encode(StateCodingTests.snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["workflow"] == nil)
    }
}
