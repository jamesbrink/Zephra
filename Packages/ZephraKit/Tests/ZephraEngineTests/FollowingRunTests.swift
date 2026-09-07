import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The canvas follows the run it was asked for, and stops following when the user looks
/// elsewhere. `current` is what is on the canvas; it is no longer whatever the engine made last.
@Suite("following the run")
@MainActor
struct FollowingRunTests {
    @Test("pressing Generate follows the run, and its frames land in the live preview")
    func generateFollowsAndFramesArrive() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        #expect(store.followsRun)
        #expect(store.isShowingRun)
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        #expect(store.livePreview?.width == 2)

        await store.settle()
        #expect(store.livePreview == nil, "a finished run leaves no frame behind")
        #expect(store.current?.pngData == MockBackend.pngData)
        #expect(!store.isShowingRun, "nothing is running any more")
    }

    @Test("a result that lands while the user is looking elsewhere leaves the canvas alone")
    func aResultDoesNotYankTheCanvas() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: store.settings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        #expect(!store.followsRun)
        await store.settle()

        #expect(store.current?.id == earlier.id, "the picture being looked at stayed")
        #expect(store.history.count == 1, "the result still entered history")
        #expect(store.history.first?.pngData == MockBackend.pngData)
        #expect(try bed.writtenFiles().count == 1, "and was still written")
    }

    @Test("watching the run again puts its result back on the canvas")
    func watchRunFollowsAgain() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: store.settings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        store.watchRun()
        #expect(store.isShowingRun)
        await store.settle()

        #expect(store.current?.pngData == MockBackend.pngData)
    }

    @Test("opening a library picture stops the canvas following, and the frame stays with the run")
    func openingStopsFollowing() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.stopFollowingRun()

        #expect(!store.followsRun)
        #expect(store.livePreview != nil, "the run's frame is still the card's to show")
        #expect(!store.isShowingRun)
        await store.settle()
    }

    @Test("queueing another run behind the one in flight keeps its frame on the canvas")
    func queueingKeepsTheFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.generate()

        #expect(store.queue.count == 1)
        #expect(store.livePreview != nil, "the frame belongs to the run, not to the press")
        #expect(store.isShowingRun)
        await store.settle()
    }

    @Test("a run that is stopped puts its frame down at once")
    func cancellingDropsTheFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update {
            $0.previewsEveryStep = true
            $0.stepDelay = .milliseconds(10)
            $0.stepOverride = 200
        }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        try await bed.waitForStep()
        try await waitForPreview(on: store)
        store.cancel()

        #expect(store.livePreview == nil)
        await store.settle()
        #expect(store.current == nil, "a stopped run publishes nothing")
    }

    @Test("the frame of one run never opens the next")
    func aNewRunStartsWithNoFrame() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.previewsEveryStep = true; $0.stepDelay = .milliseconds(5) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.generate()
        await store.settle()
        #expect(bed.control.settings.previewsEmitted > 0, "the mock did report frames")
        #expect(store.livePreview == nil)

        store.generate()
        #expect(store.livePreview == nil, "the new run starts blank")
        await store.settle()
    }

    /// Blocks until a frame has made it through the pump to the main actor, which is a moment
    /// behind the backend reporting it.
    private func waitForPreview(on store: GenerationStore) async throws {
        for _ in 0..<500 {
            if store.livePreview != nil { return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

/// The sidebar's wall and its running card are both a run to pick up again, so both move the
/// capsule's settings, not only the canvas.
@Suite("picking a run up again from the sidebar")
@MainActor
struct SidebarSelectionTests {
    @Test("selecting a library picture shows it and adopts its settings; opening only shows it")
    func selectAdoptsAndOpenDoesNot() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        try bed.library.write(LibraryAnnotationTests.image(seed: 11, prompt: "a harbour"))
        let item = try #require(LibraryScan(library: bed.library).rescan().first)
        store.settings.prompt = "a lighthouse"

        await store.open(item)
        #expect(store.current?.settings.prompt == "a harbour")
        #expect(store.settings.prompt == "a lighthouse", "looking adopts nothing")

        await store.select(item)
        #expect(store.current?.settings.prompt == "a harbour")
        #expect(store.settings.prompt == "a harbour")
        #expect(store.settings.seed == 11)
        #expect(!store.followsRun)
    }

    @Test("watching the run again puts the run's own settings back in the capsule")
    func watchRunRestoresTheRunsSettings() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.seed = 7
        var earlierSettings = store.settings
        earlierSettings.prompt = "a harbour"
        earlierSettings.seed = 11
        let earlier = GeneratedImage(
            pngData: Data([1, 2, 3]), settings: earlierSettings, modelID: store.descriptor.id,
            duration: .seconds(1))

        store.generate()
        try await bed.waitForStep()
        store.select(earlier)
        #expect(store.settings.prompt == "a harbour")
        #expect(store.settings.seed == 11)

        store.watchRun()
        #expect(store.isShowingRun)
        #expect(store.settings.prompt == "a lighthouse")
        #expect(store.settings.seed == 7)
        await store.settle()
    }

    @Test("with nothing running, watching again changes no settings")
    func watchRunWithNothingRunning() async {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"

        store.watchRun()
        #expect(store.settings.prompt == "a lighthouse")
    }
}
