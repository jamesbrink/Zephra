import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraEngine

@MainActor @Suite("Continuous publication remains readable by the pre-multi-host wire decoder")
struct LegacyPublicationTests {
    @Test func legacyCommandsAndPublication() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        // This phone sends no multiHost command and never enables the new preview subscription.
        for index in 0..<10 {
            let before = phone.envelopes.count
            let request = CompanionHostTests.request(prompt: "legacy round \(index)")
            guard case .queued = try await phone.request(.enqueue(request)) else {
                Issue.record("A legacy enqueue was refused"); await bed.shutdown(); return
            }
            try await bed.waitUntil { bed.store.history.count == index + 1 }
            bed.host.publishNow()
            _ = try await phone.request(.resync)
            try await bed.waitUntil { phone.envelopes.dropFirst(before).contains { $0.kind == .snapshot } }
            #expect(phone.failure == nil)
        }
        var snapshots = 0, deltas = 0
        for envelope in phone.envelopes {
            switch envelope.kind {
            case .snapshot:
                let value = try envelope.decode(LegacyStateSnapshot.self)
                #expect(value.hostName == "A Test Mac")
                snapshots += 1
            case .delta:
                _ = try envelope.decode(LegacyStateDelta.self)
                deltas += 1
            default: break
            }
        }
        #expect(snapshots == 11 && deltas >= 10)
        #expect(bed.host.sessions.count == 1)
        await bed.shutdown()
    }
}
