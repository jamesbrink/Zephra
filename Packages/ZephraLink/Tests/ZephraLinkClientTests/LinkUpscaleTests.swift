import Foundation
import Testing
@testable import ZephraLinkClient
import ZephraLinkProtocol

@MainActor
@Suite("Upscaling never repeats work after a lost acknowledgment")
struct LinkUpscaleTests {
    @Test func lostReplyIsNotRetried() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        bed.client.endLibraryPull()
        bed.client.requestTimeout = .milliseconds(50)
        bed.host.onCommand = { command in
            if case .upscale = command { bed.road.dropFrame() }
        }
        await #expect(throws: LinkClientError.self) {
            try await bed.client.upscale(name: "picture.png", factor: 2)
        }
        #expect(bed.host.commands.filter { $0 == .upscale(name: "picture.png", factor: 2) }.count == 1)
        #expect(bed.client.pending.isEmpty)
    }
}
