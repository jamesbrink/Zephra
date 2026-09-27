import Foundation
import Testing
import ZephraCore
import ZephraTestSupport
@testable import ZephraSnapshot

@Suite("Download and build claims share the existing volume budget")
struct TransferReservationTests {
    @Test("Same-volume build claims reserve once and release on cancellation")
    func sharedVolume() async throws {
        let scratch = Scratch("SharedVolume")
        let pool = ModelTransfers(capacity: { _ in TransferCapacity(id: "disk", available: (256 << 20) + 100) })
        let a = UUID(), b = UUID()
        let locations = ModelLocations(root: scratch.root)
        try await pool.reserve(a, model: ModelCatalog.zImageTurbo8bit, locations: locations)
        try await pool.reserve(b, model: ModelCatalog.flux2Klein4bit, locations: locations)
        try await pool.reserveBuild(a, bytes: 80, at: scratch.root)
        await #expect(throws: BackendError.self) { try await pool.reserveBuild(b, bytes: 30, at: scratch.root) }
        #expect(await pool.reservedBytes(on: "disk") == 80)
        try await pool.release(a)
        try await pool.reserveBuild(b, bytes: 100, at: scratch.root)
        #expect(await pool.reservedBytes(on: "disk") == 100)
        try await pool.release(b)
        #expect(await pool.reservedBytes(on: "disk") == 0)
    }

    @Test("Claims on distinct volumes do not consume each other's space")
    func separateVolumes() async throws {
        let scratch = Scratch("SeparateVolumes")
        let pool = ModelTransfers(capacity: { url in TransferCapacity(id: url.path, available: (256 << 20) + 100) })
        let a = UUID(), b = UUID(), left = scratch.url("left"), right = scratch.url("right")
        try await pool.reserve(a, model: ModelCatalog.zImageTurbo8bit, locations: ModelLocations(root: left))
        try await pool.reserve(b, model: ModelCatalog.flux2Klein4bit, locations: ModelLocations(root: right))
        try await pool.reserveBuild(a, bytes: 100, at: left)
        try await pool.reserveBuild(b, bytes: 100, at: right)
        #expect(await pool.reservedBytes(on: left.path) == 100)
        #expect(await pool.reservedBytes(on: right.path) == 100)
        try await pool.release(a); try await pool.release(b)
    }
}
