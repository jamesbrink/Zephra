import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// A phone loading another model over the one the Mac has in.
extension CompanionHostTests {
    @Test("a phone's Load of another model over a ready Mac swaps the weights")
    func aPhoneLoadOverAReadyMacSwaps() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        bed.store.loadingMode = .onDemand
        let before = try #require(bed.store.loadedDescriptor)
        #expect(bed.store.state == .ready)
        let other = try #require(
            ModelCatalog.all.first { $0.id != before.id && bed.store.canSelect($0) })
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.loadModel(other.id))

        #expect(reply == .ok)
        try await bed.waitUntil {
            bed.store.loadedDescriptor?.id == other.id && bed.store.state == .ready
        }
        #expect(bed.store.loadedDescriptor?.id == other.id)
        #expect(bed.engine.control.settings.unloads == 1, "the old weights went back first")
        await bed.shutdown()
    }

    @Test("a phone's Load of another model swaps under Automatic too, and a repeat is ok")
    func aPhoneLoadUnderAutomaticSwapsAndRepeats() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        #expect(bed.store.loadingMode == .automatic)
        let before = try #require(bed.store.loadedDescriptor)
        let other = try #require(
            ModelCatalog.all.first { $0.id != before.id && bed.store.canSelect($0) })
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(try await phone.request(.loadModel(other.id)) == .ok)
        // The reply went missing and the phone asks again, mid-swap and after it.
        #expect(try await phone.request(.loadModel(other.id)) == .ok)
        try await bed.waitUntil {
            bed.store.loadedDescriptor?.id == other.id && bed.store.state == .ready
        }
        #expect(try await phone.request(.loadModel(other.id)) == .ok)
        #expect(bed.engine.control.settings.unloads == 1)
        #expect(bed.engine.control.settings.loads == 2, "one swap, never a second load")
        await bed.shutdown()
    }
}
