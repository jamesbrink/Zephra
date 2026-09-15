import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The clock that gives the weights back when nobody has asked for anything in a while.
///
/// Driven through `idleWait`, the one seam the store keeps for it, so the whole suite runs in
/// milliseconds and nothing here sleeps for five minutes.
@MainActor
@Suite("Giving the weights back after an idle stretch")
struct IdleUnloadTests {
    /// A store whose idle clock fires on the next turn of the main actor.
    static func store(_ bed: EngineTestBed) -> GenerationStore {
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.idleWait = { _ in }
        return store
    }

    /// Waits for the clock to have fired and its unload to have settled, or gives up.
    static func waitForUnload(_ bed: EngineTestBed, _ store: GenerationStore) async throws {
        try await bed.waitUntil { store.loadedDescriptor == nil }
        await store.settle()
    }

    @Test("a model left sitting ready is given back")
    func readyAndIdleUnloads() async throws {
        let bed = EngineTestBed()
        let store = Self.store(bed)
        await store.bootstrap()
        #expect(store.loadedDescriptor != nil)

        store.idleUnloadDelay = .fiveMinutes
        try await Self.waitForUnload(bed, store)

        #expect(store.loadedDescriptor == nil)
        #expect(store.state == .idle)
        #expect(store.descriptor.id == ModelCatalog.default.id, "the choice survives")
        #expect(bed.control.settings.unloads == 1)
        await store.shutdown()
    }

    @Test("with the preference at Never nothing is ever given back")
    func neverKeepsTheWeights() async throws {
        let bed = EngineTestBed()
        let store = Self.store(bed)
        await store.bootstrap()
        #expect(store.idleUnloadDelay == .never, "off unless the person turned it on")

        for _ in 0..<20 { await Task.yield() }

        #expect(store.loadedDescriptor != nil)
        #expect(bed.control.settings.unloads == 0)
        await store.shutdown()
    }

    @Test("the clock does not fire while a run is in flight, and starts again once it lands")
    func arunHoldsTheClockOff() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = Self.store(bed)
        await store.bootstrap()
        store.idleUnloadDelay = .fiveMinutes
        // The clock is armed and would fire at once, so the press has to come first.
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()

        #expect(store.loadedDescriptor != nil, "the weights a run is using stay")
        #expect(store.running != nil)

        try await Self.waitForUnload(bed, store)
        #expect(store.history.count == 1, "the run landed before the weights went")
        #expect(bed.control.settings.unloads == 1)
        await store.shutdown()
    }

    @Test("an upscale holds the clock off too")
    func anupscaleHoldsTheClockOff() async throws {
        let bed = EngineTestBed()
        let store = Self.store(bed)
        await store.bootstrap()
        bed.upscalerControl.update { $0.tiles = 20; $0.tileDelay = .milliseconds(5) }
        var settings = GenerationSettings(
            prompt: "a lighthouse at dusk", size: ImageSize(width: 1024, height: 1024),
            steps: 9, guidance: 0, seed: 99)
        settings.frames = 1
        let parent = try bed.library.write(
            GeneratedImage(
                pngData: MockBackend.pngData, settings: settings,
                modelID: ModelCatalog.default.id, duration: .seconds(3)))
        store.upscale(.file(parent), factor: 2)
        try await bed.waitForTile()
        store.idleUnloadDelay = .fiveMinutes

        #expect(store.loadedDescriptor != nil)
        #expect(store.isUpscaling)
        #expect(!store.isIdleCandidate, "a picture is being made larger over those weights")

        try await Self.waitForUnload(bed, store)
        await store.shutdown()
    }

    @Test("work still waiting in the queue holds the clock off")
    func aqueuedEntryHoldsTheClockOff() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = Self.store(bed)
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate(count: 3)
        try await bed.waitForStep()
        store.idleUnloadDelay = .fiveMinutes

        #expect(!store.queue.isEmpty)
        #expect(!store.isIdleCandidate)

        try await Self.waitForUnload(bed, store)
        #expect(store.history.count == 3, "every seed ran before the weights went")
        await store.shutdown()
    }

    @Test("moving the preference back to Never stops a clock already running")
    func settingNeverStopsTheClock() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        // A clock that never finishes waiting, so the preference change is what decides it.
        let held = AsyncStream<Void>.makeStream()
        store.idleWait = { _ in for await _ in held.stream {} }
        await store.bootstrap()
        store.idleUnloadDelay = .fiveMinutes
        #expect(store.idleTask != nil)

        store.idleUnloadDelay = .never
        #expect(store.idleTask == nil, "the clock is put away rather than left running")

        held.continuation.finish()
        for _ in 0..<20 { await Task.yield() }
        #expect(store.loadedDescriptor != nil, "and its wait finishing changes nothing")
        await store.shutdown()
    }

    @Test("what counts as idle is every clause of it, asked one at a time")
    func everyClauseOfTheIdleQuestion() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.isIdleCandidate, "loaded, ready, and nothing else going")

        // Each clause on its own, over a store that is otherwise idle, so none of them is
        // standing in for `state == .ready` having already answered.
        let waiting = QueuedGeneration(model: store.descriptor, settings: store.settings)
        store.queue = [waiting]
        #expect(!store.isIdleCandidate, "seeds still waiting are not an idle Mac")
        store.queue = []

        store.running = waiting
        #expect(!store.isIdleCandidate, "nor is one whose run the state has not caught up with")
        store.running = nil

        store.upscaleTask = Task {}
        #expect(!store.isIdleCandidate, "an upscale outlives the state it puts back")
        await store.upscaleTask?.value
        store.upscaleTask = nil

        store.isSwappingModel = true
        #expect(!store.isIdleCandidate)
        store.isSwappingModel = false

        store.isStoppingPreparation = true
        #expect(!store.isIdleCandidate)
        store.isStoppingPreparation = false

        store.isShuttingDown = true
        #expect(!store.isIdleCandidate, "a Mac on its way out has nothing to gain by it")
        store.isShuttingDown = false

        #expect(store.isIdleCandidate, "and it comes back to idle when each of them is put down")
        await store.shutdown()
    }

    @Test("quitting puts the clock away rather than leaving it holding the store")
    func shutdownStopsTheClock() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        // A clock whose wait is the app's own, so only the shutdown can end it.
        await store.bootstrap()
        store.idleUnloadDelay = .oneHour
        #expect(store.idleTask != nil)

        await store.shutdown()
        #expect(store.idleTask == nil)
    }

    @Test("a load arms the clock again, so the next idle stretch counts from there")
    func aloadRearmsTheClock() async throws {
        let bed = EngineTestBed()
        let store = Self.store(bed)
        store.loadingMode = .onDemand
        store.idleUnloadDelay = .fiveMinutes
        await store.bootstrap()
        #expect(store.idleTask == nil, "nothing is loaded, so there is nothing to give back")

        store.loadModel()
        try await Self.waitForUnload(bed, store)

        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.unloads == 1, "the load armed it and it fired")
        await store.shutdown()
    }
}
