import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@MainActor @Suite("Revisioned pages remain coherent across concurrent library mutations")
struct ModernLibraryPullTests {
    @Test("A mid-list insert, delete or same-count replacement restarts the revision", arguments: [0, 1, 2])
    func changesBetweenPages(_ change: Int) async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        bed.host.library = (0..<250).map { ClientFixtures.entry("picture-\($0).png") }
        var changed = false
        bed.host.onCommand = { command in
            guard !changed, case .multiHost(.listing(let offset, _, _)) = command, offset == 100 else { return }
            changed = true
            if change != 0 { bed.host.library.removeFirst() }
            if change != 1 { bed.host.library.insert(ClientFixtures.entry("replacement.png"), at: 0) }
        }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        var snapshot = ClientFixtures.snapshot
        snapshot.multiHost = true; snapshot.libraryCount = 250
        try await bed.host.announce(snapshot, kind: .snapshot)
        try await LinkGapRecoveryTests.settle(within: .seconds(5)) { bed.client.libraryIsComplete }
        #expect(changed)
        #expect(bed.client.library == bed.host.library)
        let starts = bed.host.commands.filter {
            if case .multiHost(.listing(let offset, _, _)) = $0 { return offset == 0 }; return false
        }
        #expect(starts.count == 2)
        #expect(!bed.host.commands.contains { if case .libraryPage = $0 { return true }; return false })
    }
    @Test("A delta immediately behind the last page is retained")
    func finalPageDelta() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        bed.host.library = (0..<150).map { ClientFixtures.entry("picture-\($0).png") }
        var sent = false
        bed.host.afterReply = { command in
            guard !sent, case .multiHost(.listing(let offset, _, _)) = command, offset == 100 else { return }
            sent = true
            let extra = ClientFixtures.entry("after-page.png")
            bed.host.library.append(extra)
            try await bed.host.announce(StateDelta.library(.upserted([extra])), kind: .delta)
        }
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        var snapshot = ClientFixtures.snapshot
        snapshot.multiHost = true; snapshot.libraryCount = 150
        try await bed.host.announce(snapshot, kind: .snapshot)
        try await LinkGapRecoveryTests.settle(within: .seconds(5)) {
            bed.client.libraryIsComplete && bed.client.library.count == 151
        }
        #expect(sent)
        #expect(Set(bed.client.library.map(\.fileName)) == Set(bed.host.library.map(\.fileName)))
    }
}
