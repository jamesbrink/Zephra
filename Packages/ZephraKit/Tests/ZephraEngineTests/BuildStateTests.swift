import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Building a model before it can be loaded")
struct BuildStateTests {
    @Test("a family that packs its download reports building between downloading and loading")
    func buildingIsItsOwnState() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.buildEvents = 3; $0.buildDelay = .milliseconds(40) }
        let store = bed.store(descriptor: ModelCatalog.flux2Klein4bit)
        store.warmsUpAfterLoad = false
        let task = Task { await store.bootstrap() }
        var sawBuilding = false
        // A generous bound: the whole suite runs in parallel and a busy machine can hold the
        // main actor for longer than a build event lasts.
        for _ in 0..<1000 {
            if case .building(let progress) = store.state {
                sawBuilding = true
                #expect(progress.component == "transformer")
                #expect(progress.totalComponents == 3)
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        await task.value
        #expect(sawBuilding, "the store showed .building while the mock packed")
        #expect(store.state == .ready)
        #expect(bed.control.settings.builds == 1)
    }

    @Test("a family whose download is what gets loaded never builds")
    func plainFamiliesSkipTheBuild() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(bed.control.settings.builds == 0)
    }

    @Test("stopping during a build abandons it and returns to idle")
    func cancelDuringBuild() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.buildEvents = 50; $0.buildDelay = .milliseconds(20) }
        let store = bed.store(descriptor: ModelCatalog.flux2Klein4bit)
        store.warmsUpAfterLoad = false
        let task = Task { await store.bootstrap() }
        for _ in 0..<1000 {
            if case .building = store.state { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        store.cancel()
        await task.value
        await store.settle()
        #expect(store.state == .idle)
        #expect(bed.control.settings.loads == 0, "the load never started")
    }
}
