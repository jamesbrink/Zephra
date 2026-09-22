import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// A run that has not the room over resident weights reads them from disk instead.
///
/// The load path has stepped down rather than refused since 2026-09-13; this is the same step,
/// made after the weights are in. Under Automatic it is a load, not a sentence: the job goes
/// back to the head of the queue, the model is reloaded streamed, and the job runs.
@MainActor
@Suite("A run with no room over resident weights streams instead")
struct RunResidencyStepDownTests {
    /// The model, `WeightResidencyStoreTests.streamable`: 30 GB held, 9 GB streamed.
    static let model = WeightResidencyStoreTests.streamable

    /// A family that never learned to stream, so there is nothing to step down to.
    static let unstreamable = ModelDescriptor(
        id: "unstreamable", displayName: "Unstreamable", variantName: nil, backend: .zImage,
        source: ModelCatalog.default.source, quantization: .int4, downloadBytes: 0,
        residentBytes: 21_000_000_000, peakBytes: 30_000_000_000,
        tiledPeakBytes: 26_000_000_000, streamedPeakBytes: 0, maxPromptTokens: 512,
        capabilities: ModelCatalog.default.capabilities, builtBytes: 0)

    /// What the allocator says it is holding once the weights are in. Small enough that a
    /// streamed run is still charged something, so "streaming also fell short" is expressible.
    static let held = MemorySnapshot(activeBytes: 2_000_000_000, cacheBytes: 0, peakBytes: 0)

    /// Room for the streamed run's 7 GB and not the resident run's 28 GB.
    static func roomForStreamedRunOnly() -> MachineMemory {
        MachineMemory(physicalBytes: 64 << 30, availableBytes: 10_000_000_000)
    }

    /// Room for neither.
    static func roomForNeither() -> MachineMemory {
        MachineMemory(physicalBytes: 64 << 30, availableBytes: 5_000_000_000)
    }

    /// A store holding `model` resident, with the machine still roomy.
    static func loadedResident(
        _ bed: EngineTestBed, descriptor: ModelDescriptor = RunResidencyStepDownTests.model,
        mode: WeightResidencyMode = .automatic
    ) async -> GenerationStore {
        bed.memoryBudget = MemoryGuardStoreTests.roomyEnoughToHold
        let store = bed.store(descriptor: descriptor)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: mode, budget: MemoryGuardStoreTests.roomyEnoughToHold)
        await store.bootstrap()
        bed.control.update { $0.memory = held }
        return store
    }

    @Test("the job goes back to the head of the queue, the model is reloaded streamed, and it runs")
    func therunStepsDownAndLands() async throws {
        let bed = EngineTestBed()
        let store = await Self.loadedResident(bed)
        #expect(store.loadedResidency == .resident)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        bed.machineMemory = Self.roomForStreamedRunOnly()

        store.generate()
        try await bed.waitUntil { store.history.count == 1 }
        await store.settle()

        #expect(store.loadedResidency == .streamed)
        #expect(bed.control.settings.lastResidency == .streamed)
        #expect(bed.control.settings.loads == 2, "read in once more, and only once")
        #expect(store.state == .ready)
        #expect(store.queue.isEmpty)
        #expect(await bed.claimCount(store) == 1, "one lease across the reload")
        await store.shutdown()
    }

    @Test("the refused job keeps its place at the head and its batch")
    func thejobKeepsItsPlace() async throws {
        let bed = EngineTestBed()
        let store = await Self.loadedResident(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        bed.machineMemory = Self.roomForStreamedRunOnly()

        store.generate(count: 3)
        let batch = try #require(store.queue.first?.batchID ?? store.running?.batchID)
        try await bed.waitUntil { store.history.count == 3 }
        await store.settle()

        #expect(store.history.count == 3, "every seed of the press ran, none was dropped")
        #expect(store.history.allSatisfy { $0.batchID == batch }, "and all under one batch")
        #expect(bed.control.settings.loads == 2)
        await store.shutdown()
    }

    @Test("where streaming is short too the refusal stands, and drops only that batch")
    func streamingShortToo() async throws {
        let bed = EngineTestBed()
        let store = await Self.loadedResident(bed)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        bed.machineMemory = Self.roomForNeither()

        store.generate()
        await store.settle()

        guard case .failed(let error) = store.state,
            case .insufficientMemory(let shortfall) = error
        else {
            Issue.record("expected a memory refusal, got \(store.state)")
            await store.shutdown()
            return
        }
        #expect(shortfall.phase == .run)
        #expect(shortfall.remedy == .quitOtherApps, "Automatic is already the setting")
        #expect(bed.control.settings.loads == 1, "nothing was read in again")
        #expect(store.loadedResidency == .resident)
        #expect(store.queue.isEmpty)
        #expect(store.history.isEmpty)
        await store.shutdown()
    }

    @Test("under Never the refusal stands, since holding the weights is what was asked for")
    func neverDoesNotStepDown() async throws {
        let bed = EngineTestBed()
        let store = await Self.loadedResident(bed, mode: .never)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        bed.machineMemory = Self.roomForStreamedRunOnly()

        store.generate()
        await store.settle()

        guard case .failed(.insufficientMemory(let shortfall)) = store.state else {
            Issue.record("expected a memory refusal, got \(store.state)")
            await store.shutdown()
            return
        }
        #expect(shortfall.phase == .run)
        #expect(shortfall.remedy == .streamFromDisk, "and the remedy is the preference")
        #expect(bed.control.settings.loads == 1)
        await store.shutdown()
    }

    @Test("a family that cannot stream is refused rather than reloaded")
    func anunstreamableFamilyIsRefused() async throws {
        let bed = EngineTestBed()
        let store = await Self.loadedResident(bed, descriptor: Self.unstreamable)
        store.settings.prompt = "a lantern on a jetty"
        store.settings.steps = 2
        bed.machineMemory = Self.roomForStreamedRunOnly()

        store.generate()
        await store.settle()

        guard case .failed(.insufficientMemory(let shortfall)) = store.state else {
            Issue.record("expected a memory refusal, got \(store.state)")
            await store.shutdown()
            return
        }
        #expect(shortfall.phase == .run)
        #expect(bed.control.settings.loads == 1)
        #expect(store.loadedResidency == .resident)
        await store.shutdown()
    }
}
