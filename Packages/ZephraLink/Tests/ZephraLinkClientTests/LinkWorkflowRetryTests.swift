import Foundation
import Testing
@testable import ZephraLinkClient
import ZephraLinkProtocol

@MainActor @Suite("Transfer edits cannot overtake a newer user decision through retry")
struct LinkWorkflowRetryTests {
    @Test(arguments: [WorkflowCommand.download("model"), .pause("model"), .cancel("model")])
    func lostReplyIsNotRetried(work: WorkflowCommand) async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        bed.client.requestTimeout = .milliseconds(50)
        bed.host.onCommand = { command in
            if command == .workflow(work) { bed.road.dropFrame() }
        }
        await #expect(throws: LinkClientError.self) { try await bed.client.request(.workflow(work)) }
        #expect(bed.host.commands.filter { $0 == .workflow(work) }.count == 1)
        #expect(bed.client.pending.isEmpty)
    }
}
