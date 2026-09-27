import Foundation
import Testing
@testable import ZephraLinkClient
import ZephraLinkProtocol

@MainActor @Suite("Unscoped destructive controls apply only once")
struct LinkDestructiveRetryTests {
    @Test(arguments: [Command.cancel, .clearQueue])
    func lostAcknowledgment(command: Command) async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        let (clock, expire) = AsyncStream<Void>.makeStream()
        defer { expire.finish() }
        bed.client.requestSleep = { _ in for await _ in clock { break }; try Task.checkCancellation() }
        bed.host.onCommand = { received in if received == command { bed.road.dropFrame() } }
        let task = Task { try await bed.client.request(command) }
        try await LinkGapRecoveryTests.settle { bed.host.commands.contains(command) }
        expire.yield(())
        do { _ = try await task.value; Issue.record("A lost reply must be uncertain") }
        catch let error as LinkError { #expect(error.reason.contains("may already")) }
        bed.client.requestSleep = { try await Task.sleep(for: $0) }
        let subsequent = GenerationRequest(
            modelID: ClientFixtures.model.id, count: 1, settings: ClientFixtures.settings)
        _ = try await bed.client.enqueue(subsequent)
        #expect(bed.host.commands.contains(.enqueue(subsequent)))
        #expect(bed.host.commands.filter { $0 == command }.count == 1)
        #expect(bed.client.pending.isEmpty)
    }

    @Test("A command that was never sent remains a definite connection error")
    func offline() async throws {
        let bed = LinkClientUnderTest()
        await #expect(throws: LinkClientError.notConnected) { try await bed.client.clearQueue() }
        await #expect(throws: LinkClientError.notConnected) { try await bed.client.cancel() }
        await bed.host.stop()
    }

    @Test("Clear Queue throws the host's definite refusal")
    func refused() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        let error = LinkError(code: .busy, reason: "The queue is unavailable.")
        bed.host.reply = .error(error)
        await #expect(throws: error) { try await bed.client.clearQueue() }
    }

    @Test("Disconnection after Stop was sent is uncertain and never retries")
    func disconnectedAfterSending() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        bed.host.beforeReply = { command in
            if command == .cancel { await bed.client.disconnect() }
        }
        do { try await bed.client.cancel(); Issue.record("A lost connection must be uncertain") }
        catch let error as LinkError { #expect(error.reason.contains("may already")) }
        #expect(bed.host.commands.filter { $0 == .cancel }.count == 1)
    }

    @Test("An unexpected acknowledgment cannot establish a destructive command's outcome")
    func unexpectedAcknowledgment() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        bed.host.reply = .queued(batchID: UUID())
        do { try await bed.client.clearQueue(); Issue.record("An invalid acknowledgment must be uncertain") }
        catch let error as LinkError { #expect(error.reason.contains("may already")) }
        #expect(bed.host.commands.filter { $0 == .clearQueue }.count == 1)
    }
}
