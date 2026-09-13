import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkHost

@MainActor
@Suite("Durable host receipts prevent replay across sessions and crashes")
struct GenerationReceiptsTests {
    @Test("A restart preserves identity but does not invent queue recovery")
    func restart() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let peer = DeviceIdentity().publicKeys
        let id = UUID(), batch = UUID()
        let receipt = GenerationReceipt(requestID: id, digest: "immutable", batchID: batch, status: .accepted)
        try GenerationReceipts(root: root).write(receipt, peer: peer)
        let recovered = try GenerationReceipts(root: root).read(peer: peer, request: id)
        #expect(recovered?.status == .unknown)
        #expect(recovered?.batchID == batch)
        #expect(recovered?.digest == "immutable")
        #expect(try GenerationReceipts(root: root).read(peer: DeviceIdentity().publicKeys, request: id) == nil)
    }

    @Test("Partial completion remains active, then interruption is explicit and expiry leaves a tombstone")
    func lifecycle() throws {
        let receipts = GenerationReceipts()
        let peer = DeviceIdentity().publicKeys, batch = UUID(), id = UUID()
        var receipt = GenerationReceipt(requestID: id, digest: "job", batchID: batch, status: .accepted,
            recordedAt: Date(timeIntervalSince1970: 0))
        receipt.expectedCount = 2
        try receipts.write(receipt, peer: peer)
        try receipts.reconcile(active: [batch], completed: [batch: 1], now: Date(timeIntervalSince1970: 10))
        #expect(try receipts.read(peer: peer, request: id)?.status == .accepted)
        try receipts.reconcile(active: [], completed: [batch: 1], now: Date(timeIntervalSince1970: 20))
        #expect(try receipts.read(peer: peer, request: id)?.status == .interrupted)
        try receipts.reconcile(active: [], completed: [:], now: Date(timeIntervalSince1970: 40 * 86_400))
        let tombstone = try receipts.read(peer: peer, request: id)
        #expect(tombstone?.status == .unknown)
        #expect(tombstone?.digest == "job")
        #expect(tombstone?.batchID == nil)
    }

    @Test("Corrupt persisted receipts refuse reads and writes rather than allow duplicate work")
    func corruptStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("broken".utf8).write(to: root.appending(path: "broken.json"))
        let receipts = GenerationReceipts(root: root), peer = DeviceIdentity().publicKeys
        #expect(throws: (any Error).self) { try receipts.read(peer: peer, request: UUID()) }
        #expect(throws: (any Error).self) {
            try receipts.write(GenerationReceipt(requestID: UUID(), digest: "job", status: .prepared), peer: peer)
        }
    }
}
