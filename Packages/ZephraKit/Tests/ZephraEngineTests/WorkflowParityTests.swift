import Foundation
import Testing
import ZephraCore
@testable import ZephraEngine

@MainActor @Suite("Queue ordering and admitted prompt history")
struct WorkflowParityTests {
    private func job(_ batch: UUID, index: Int = 0) -> QueuedGeneration {
        QueuedGeneration(model: ModelCatalog.default,
            settings: .defaults(for: ModelCatalog.default), batchID: batch, batchIndex: index)
    }
    @Test func reorderKeepsSeedOrderAndRejectsStaleIntent() {
        let a = UUID(), b = UUID(), c = UUID()
        let original = [job(a), job(a, index: 1), job(b), job(c)]
        let store = GenerationStore.preview(state: .ready, queue: original)
        #expect(store.reorderQueue(batches: [c, a, b], expectedEntries: original.map(\.id)))
        #expect(store.queue.map(\.id) == [original[3].id, original[0].id, original[1].id, original[2].id])
        #expect(!store.reorderQueue(batches: [a, b, c], expectedEntries: original.map(\.id)), "another editor's old order cannot overwrite the change")
        #expect(!store.reorderQueue(batches: [a, b, b], expectedEntries: store.queue.map(\.id)))
        let seen = store.queue.map(\.id)
        store.removeFromQueue(original[2].id)
        #expect(!store.reorderQueue(batches: [c, a], expectedEntries: seen))
    }
    @Test func runningAndPreparingBatchesStayPinned() {
        let a = UUID(), b = UUID()
        let flight = job(a), waiting = [job(a, index: 1), job(b)]
        let store = GenerationStore.preview(state: .ready, running: flight, queue: waiting)
        #expect(!store.reorderQueue(batches: [b, a], expectedEntries: waiting.map(\.id)))
        store.running = nil; store.isSwitchingForQueue = true
        #expect(!store.reorderQueue(batches: [b, a], expectedEntries: waiting.map(\.id)))
        #expect(store.queue == waiting)
    }
    @Test func historySurvivesFailurePersistsAndBoundsBytes() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let history = PromptHistory(file: file)
        let id = UUID()
        history.record("a prompt that later failed", id: id)
        history.record("a retry of the same request", id: id)
        #expect(history.entries.count == 1)
        #expect(PromptHistory(file: file).entries == history.entries)
        for _ in 0..<120 { history.record(String(repeating: "😀", count: 1000), id: UUID()) }
        #expect(history.entries.count <= 100)
        #expect(history.entries.reduce(0) { $0 + $1.prompt.utf8.count } <= 262_144)
        #expect(history.failure == nil)
    }
    @Test func recallRestoresDraftAndEditsStartNewNavigation() {
        var recall = PromptRecall()
        #expect(recall.step(older: true, current: "unsent draft", prompts: ["new", "old"]) == "new")
        #expect(recall.step(older: true, current: "new", prompts: ["new", "old"]) == "old")
        #expect(recall.step(older: false, current: "old", prompts: ["new", "old"]) == "new")
        #expect(recall.step(older: false, current: "new", prompts: ["new", "old"]) == "unsent draft")
        #expect(recall.step(older: true, current: "edited", prompts: ["new", "old"]) == "new")
        #expect(recall.step(older: false, current: "new", prompts: ["new", "old"]) == "edited")
    }
}
