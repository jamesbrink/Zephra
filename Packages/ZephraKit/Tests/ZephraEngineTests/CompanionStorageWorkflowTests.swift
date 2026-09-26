import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraLinkProtocol
@testable import ZephraEngine

@MainActor @Suite("Remote model storage deletion settles and protects replacements")
struct CompanionStorageWorkflowTests {
    private final class InventoryBox { var value: ModelInventory! }
    @Test func deletingInUseAndReplacementFiles() async throws {
        let inventory = InventoryBox()
        let bed = CompanionTestBed(modelInventory: { inventory.value })
        inventory.value = ModelInventory(catalog: [], cache: bed.engine.directory,
            locations: bed.store.modelLocations)
        let folder = bed.store.modelLocations.root.appendingPathComponent("retired-test")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("quantization.json"))
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        guard case .workflow(.storage(let rows)) = try await phone.request(.workflow(.storage)) else {
            Issue.record("No inventory"); await bed.shutdown(); return
        }
        let row = try #require(rows.first { $0.name == "retired-test" })
        #expect((row.bytes ?? 0) >= 2)
        bed.store.loadedDirectory = folder
        guard case .error(let refusal) = try await phone.request(.workflow(.delete(id: UUID(), token: row.id))) else {
            Issue.record("In-use files were deleted"); await bed.shutdown(); return
        }
        #expect(refusal.code == .busy)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        bed.store.loadedDirectory = nil
        let deletion = Command.workflow(.delete(id: UUID(), token: row.id))
        #expect(try await phone.request(deletion) == .ok)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: folder.appendingPathComponent("quantization.json"))
        #expect(try await phone.request(deletion) == .ok)
        #expect(FileManager.default.fileExists(atPath: folder.path), "a lost-reply retry cannot delete replacement files")
        guard case .error = try await phone.request(.workflow(.delete(id: UUID(), token: row.id))) else {
            Issue.record("Consumed token reused"); await bed.shutdown(); return
        }
        await bed.shutdown()
    }
    @Test func removalFailureIsNotAcknowledgedAsSuccess() async throws {
        let inventory = InventoryBox()
        let bed = CompanionTestBed(modelInventory: { inventory.value })
        inventory.value = ModelInventory(catalog: [], cache: bed.engine.directory, locations: bed.store.modelLocations,
            remove: { _ in throw CocoaError(.fileWriteNoPermission) })
        let folder = bed.store.modelLocations.root.appendingPathComponent("failed-delete")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("quantization.json"))
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        guard case .workflow(.storage(let rows)) = try await phone.request(.workflow(.storage)) else {
            Issue.record("No inventory"); await bed.shutdown(); return
        }
        let row = try #require(rows.first)
        let operation = Command.workflow(.delete(id: UUID(), token: row.id))
        let answer = try await phone.request(operation)
        guard case .error(let error) = answer else { Issue.record("Failure acknowledged as success"); await bed.shutdown(); return }
        #expect(error.reason.contains("Couldn't delete"))
        #expect(try await phone.request(operation) == answer)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        await bed.shutdown()
    }
}
