import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What a phone is told about the models this Mac has not the memory to hold.
///
/// The verdict is the Mac's, stamped into every `ModelSummary` the snapshot carries, for the
/// reason `canQueue` is stamped into `EngineStateDTO`: the phone has no catalog, no measured
/// peak and no idea what this Mac's GPU may keep, so a phone working it out would be a phone
/// that can disagree with the Mac about which models are on offer.
extension CompanionHostTests {
    /// A budget the catalog straddles, as `MemoryGuardStoreTests` uses it: klein runs tiled,
    /// Qwen-Image streams, and LTX-2.5 with sound is over even its streamed figure.
    static let straddling = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 11_000_000_000)

    /// The catalog entry that budget cannot hold.
    static let tooLarge = ModelCatalog.ltx2DistilledAudio4bit

    @Test("the models a phone is sent say which of them this Mac can hold, and what they need")
    func theSnapshotGreysWhatTheMacCannotHold() async throws {
        let bed = CompanionTestBed()
        bed.store.memoryBudget = Self.straddling
        let phone = try await bed.pairedPhone()

        let snapshot = try await phone.snapshot()

        let tight = try #require(snapshot.models.first { $0.id == Self.tooLarge.id })
        #expect(!tight.isSelectable)
        #expect(
            tight.memoryNote
                == ModelCatalog.fit(Self.tooLarge, budget: Self.straddling).label,
            "the Mac's own words, not a second spelling of them")
        #expect(
            snapshot.models.contains { $0.isSelectable },
            "a budget that greyed every model would say nothing")
        #expect(snapshot.model.isSelectable, "the Mac does not run a model it cannot hold")
        await bed.shutdown()
    }

    @Test("choosing a model this Mac cannot hold is refused as the request it is")
    func switchingToAModelTheMacCannotHoldIsRefused() async throws {
        let bed = CompanionTestBed()
        bed.store.memoryBudget = Self.straddling
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let before = bed.store.descriptor.id

        let reply = try await phone.request(.switchModel(Self.tooLarge.id))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            return
        }
        // A bad request rather than a busy Mac: this is the machine, not the moment, so asking
        // again in a while is worth nothing — and it is the answer `remoteAdmission` gives a
        // generation on the same model.
        #expect(error.code == .badRequest)
        #expect(
            error.reason
                == ModelCatalog.fit(Self.tooLarge, budget: Self.straddling)
                    .reason(for: Self.tooLarge, budget: Self.straddling))
        #expect(bed.store.descriptor.id == before, "and the Mac's own capsule did not move")
        await bed.shutdown()
    }

    @Test("a model this Mac can hold is still switched to, and answered ok")
    func switchingToAModelTheMacCanHoldStillWorks() async throws {
        let bed = CompanionTestBed()
        bed.store.memoryBudget = Self.straddling
        let phone = try await bed.pairedPhone()
        let snapshot = try await phone.snapshot()
        let holdable = try #require(
            snapshot.models.first { $0.isSelectable && $0.id != bed.store.descriptor.id })

        let reply = try await phone.request(.switchModel(holdable.id))

        #expect(reply == .ok)
        #expect(bed.store.descriptor.id == holdable.id)
        await bed.shutdown()
    }
}
