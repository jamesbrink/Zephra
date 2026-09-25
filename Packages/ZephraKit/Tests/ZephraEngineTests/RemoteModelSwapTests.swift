import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// A request on a model that is not the one in: a swap, then a run.
///
/// The weights in now go back before the next model's are read, so a request naming another
/// model is judged the way its own load and run will be — at that model's residency, with
/// Zephra's own allocator counted as free — never as a run on top of weights about to be
/// released. And Load from `.ready` over another model's weights is the swap its tooltip names.
@MainActor
@Suite("A request on another model is judged as the swap it is")
struct RemoteModelSwapTests {
    static let loaded = ModelCatalog.flux2Klein4bit
    static let other = ModelCatalog.default

    /// klein held resident on a budget that streams Z-Image 8-bit.
    static func kleinResident(_ bed: EngineTestBed) async throws -> GenerationStore {
        bed.memoryBudget = MemoryGuardStoreTests.straddling
        let store = bed.store(descriptor: loaded)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: .automatic, budget: MemoryGuardStoreTests.straddling)
        await store.bootstrap()
        try #require(store.loadedDescriptor?.id == loaded.id)
        try #require(store.loadedResidency == .resident)
        try #require(
            store.weightResidencyPolicy.residency(for: other) == .streamed,
            "the other model streams on this budget")
        return store
    }

    static func request(for model: ModelDescriptor) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: model)
        settings.prompt = "a lantern on a jetty"
        return settings
    }

    @Test("a phone's request on another model is admitted where the swap leaves room for it")
    func admittedWhereTheSwapLeavesRoom() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        // klein's weights hold 3 GB; 5 GB more is free. Z-Image 8-bit streamed peaks at 6.42 GB,
        // which fits once klein is given back. Charged as a resident run on top of klein — the
        // old reading — it was 14.9 GB against 5, and refused.
        bed.control.update {
            $0.memory = MemorySnapshot(activeBytes: 3_000_000_000, cacheBytes: 0, peakBytes: 0)
        }
        bed.machineMemory = MachineMemory(physicalBytes: 16 << 30, availableBytes: 5_000_000_000)
        let settings = Self.request(for: Self.other)
        // The old reading, pinned so it cannot come back: a run on top of klein's allocator.
        #expect(
            store.memoryGuard.runShortfall(
                for: Self.other, residency: .resident, mode: .automatic,
                tile: store.vaeTile(for: Self.other), settings: settings,
                machine: bed.machineMemory, runtime: bed.control.settings.memory) != nil)

        #expect(store.remoteAdmission(for: Self.other, settings: settings) == .admitted)
        #expect(store.enqueue(settings, on: Self.other) != nil)
        try await bed.waitUntil { bed.control.settings.generations == 1 }
        #expect(store.loadedDescriptor?.id == Self.other.id, "the swap ran")
        #expect(bed.control.settings.unloads == 1, "klein went back first")
        await store.shutdown()
    }

    @Test("a machine with no room even after the swap still refuses, with the swap's figure")
    func refusedWhereEvenTheSwapHasNoRoom() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        bed.control.update {
            $0.memory = MemorySnapshot(activeBytes: 1_000_000_000, cacheBytes: 0, peakBytes: 0)
        }
        bed.machineMemory = MachineMemory(physicalBytes: 16 << 30, availableBytes: 1_000_000_000)

        let admission = store.remoteAdmission(
            for: Self.other, settings: Self.request(for: Self.other))
        guard case .refused(let reason) = admission else {
            Issue.record("expected a refusal, got \(admission)")
            return
        }
        #expect(reason.hasPrefix("\(Self.other.fullName) needs 6.4 GB and 2 GB is free."))
        await store.shutdown()
    }

    @Test("the loaded model's own run is still charged on top of its weights")
    func theLoadedModelIsUnchanged() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        let settings = Self.request(for: Self.loaded)
        #expect(
            store.runShortfall(for: Self.loaded, settings: settings)
                == store.memoryGuard.runShortfall(
                    for: Self.loaded, residency: .resident, mode: .automatic,
                    tile: store.vaeTile(for: Self.loaded), settings: settings,
                    machine: bed.machineMemory, runtime: bed.control.settings.memory))
        await store.shutdown()
    }

    @Test("Load from ready over another model's weights swaps them, releasing the old first")
    func loadFromReadySwaps() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        store.loadingMode = .onDemand
        #expect(!store.canLoad(Self.loaded), "the model in has nothing to load")
        #expect(store.canLoad(Self.other), "another model's load from ready is a swap")

        store.switchModel(to: Self.other)
        #expect(store.canLoad(store.descriptor))
        store.loadModel()
        try await bed.waitUntil { store.state == .ready && !store.isSwappingModel }

        #expect(store.state == .ready)
        #expect(store.loadedDescriptor?.id == Self.other.id)
        #expect(bed.control.settings.unloads == 1, "klein was given back")
        #expect(bed.control.settings.loads == 2)
        await store.shutdown()
    }

    @Test("a run that would not fit held after the swap is admitted where streaming fits")
    func theSwapStepsDownToStreaming() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = MemoryGuardStoreTests.roomyEnoughToHold
        let store = bed.store(descriptor: Self.loaded)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: .automatic, budget: MemoryGuardStoreTests.roomyEnoughToHold)
        await store.bootstrap()
        try #require(store.weightResidencyPolicy.residency(for: Self.other) == .resident)
        bed.control.update {
            $0.memory = MemorySnapshot(activeBytes: 3_000_000_000, cacheBytes: 0, peakBytes: 0)
        }
        // 28 GB once klein goes back: Z-Image 8-bit's load fits held, and a 2048 run on it
        // would not (about 57 GB), but streamed it is about 23 GB.
        bed.machineMemory = MachineMemory(physicalBytes: 64 << 30, availableBytes: 25_000_000_000)
        var settings = Self.request(for: Self.other)
        settings.size = ImageSize(width: 2048, height: 2048)

        #expect(store.remoteAdmission(for: Self.other, settings: settings) == .admitted)
        bed.machineMemory = MachineMemory(physicalBytes: 64 << 30, availableBytes: 15_000_000_000)
        #expect(store.remoteAdmission(for: Self.other, settings: settings) != .admitted)
        await store.shutdown()
    }

    @Test("a request the load itself would refuse is refused before it is queued")
    func theLoadsOwnVerdictComesFirst() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        // Held whole by choice, on a budget its held peak exceeds, with the machine itself
        // roomy: the swap-run figure alone has no ceiling and would admit what the load's own
        // check, capped at the budget, then refuses.
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: .never, budget: MemoryGuardStoreTests.straddling)
        bed.machineMemory = MachineMemory(physicalBytes: 64 << 30, availableBytes: 40_000_000_000)

        let admission = store.remoteAdmission(
            for: Self.other, settings: Self.request(for: Self.other))
        guard case .refused(let reason) = admission else {
            Issue.record("expected the load's refusal, got \(admission)")
            return
        }
        #expect(reason.hasSuffix(MemoryShortfall.Remedy.streamFromDisk.sentence))
        #expect(store.queue.isEmpty)
        await store.shutdown()
    }

    @Test("with nothing loaded, a request is charged its model's weights as well as its run")
    func nothingLoadedIsChargedTheWeights() async throws {
        let bed = EngineTestBed()
        bed.memoryBudget = MemoryGuardStoreTests.straddling
        let store = bed.store(descriptor: Self.other)
        store.warmsUpAfterLoad = false
        store.loadingMode = .onDemand
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: .automatic, budget: MemoryGuardStoreTests.straddling)
        await store.bootstrap()
        try #require(store.loadedDescriptor == nil)
        // Room for the streamed transient (5.45 GB) and not for the streamed peak (6.42 GB).
        bed.machineMemory = MachineMemory(physicalBytes: 16 << 30, availableBytes: 6_000_000_000)

        let admission = store.remoteAdmission(
            for: Self.other, settings: Self.request(for: Self.other))
        guard case .refused(let reason) = admission else {
            Issue.record("expected a refusal, got \(admission)")
            return
        }
        #expect(reason.hasPrefix("\(Self.other.fullName) needs 6.4 GB and 6 GB is free."))
        await store.shutdown()
    }

    @Test("bootstrap again over a picture's waiting model swaps nothing")
    func aSecondBootstrapDoesNotSwap() async throws {
        let bed = EngineTestBed()
        let store = try await Self.kleinResident(bed)
        store.adopt(Self.other)
        store.modelAwaitsGenerate = true

        await store.bootstrap()
        await store.settle()

        #expect(store.loadedDescriptor?.id == Self.loaded.id, "the weights stay where they were")
        #expect(store.modelAwaitsGenerate)
        #expect(bed.control.settings.unloads == 0)
        await store.shutdown()
    }
}
