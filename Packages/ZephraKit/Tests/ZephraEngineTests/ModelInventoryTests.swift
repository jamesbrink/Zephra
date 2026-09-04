import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

@testable import ZephraEngine

@Suite("Model inventory")
@MainActor
struct ModelInventoryTests {
    @Test("a refresh lists what is on disk and measures it")
    func refreshListsAndMeasures() async throws {
        let scratch = Scratch("ModelInventory")
        try scratch.write(String(repeating: "x", count: 4096), to: "models/z-image-turbo-4bit/model_index.json")
        let inventory = ModelInventory(
            cache: scratch.url("hub"), builtIn: scratch.url("models"), remove: { _ in })

        await inventory.refresh()
        let item = try #require(inventory.items.first)
        #expect(inventory.items.count == 1)
        #expect(item.kind == .built)
        #expect(item.modelIDs == ["z-image-turbo-4bit"])
        #expect((item.bytes ?? 0) >= 4096)
        #expect(inventory.totalBytes == item.bytes)
        #expect(!inventory.isMeasuring)
    }

    @Test("deleting removes the directory and reads the list again")
    func deleteRemovesAndRefreshes() async throws {
        let scratch = Scratch("ModelInventory")
        try scratch.make("models/z-image-turbo-4bit/model_index.json")
        let inventory = ModelInventory(
            cache: scratch.url("hub"), builtIn: scratch.url("models"),
            remove: { try FileManager.default.removeItem(at: $0.url) })
        await inventory.refresh()
        let item = try #require(inventory.items.first)

        await inventory.delete(item)
        #expect(inventory.items.isEmpty)
        #expect(inventory.lastFailure == nil)
        #expect(!scratch.hasFile("models/z-image-turbo-4bit/model_index.json"))
    }

    @Test("a removal that fails is reported and the list still re-read")
    func failedDeleteIsReported() async throws {
        struct Refused: Error {}
        let scratch = Scratch("ModelInventory")
        try scratch.make("models/z-image-turbo-4bit/model_index.json")
        let inventory = ModelInventory(
            cache: scratch.url("hub"), builtIn: scratch.url("models"), remove: { _ in throw Refused() })
        await inventory.refresh()
        let item = try #require(inventory.items.first)

        await inventory.delete(item)
        #expect(inventory.lastFailure?.contains("Z-Image Turbo · 4-bit") == true)
        #expect(inventory.items.count == 1, "nothing was removed, so nothing leaves the list")
    }
}
