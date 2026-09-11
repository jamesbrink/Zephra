import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// Frames of the run in flight on their way to a phone: encoded small, and not every one of
/// them.
@MainActor
@Suite("Preview frames reach the phone as JPEG, and not all of them")
struct CompanionPreviewTests {
    /// A frame of one flat colour, the size the engine's own previews are capped at being far
    /// larger than anything this suite needs to encode.
    static func frame(_ byte: UInt8, edge: Int = 8) -> GenerationPreview {
        GenerationPreview(
            width: edge, height: edge, pixels: Data(repeating: byte, count: edge * edge * 4))
    }

    @Test("a frame crosses as JPEG at the size the engine made it")
    func frameIsJPEG() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        bed.store.livePreview = Self.frame(0x40)

        let preview = try await phone.waitFor { (try? phone.previews())?.first }
        #expect(preview.jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]), "a JPEG's own first bytes")
        #expect(preview.width == 8)
        #expect(preview.height == 8)
        await bed.shutdown()
    }

    @Test("frames arriving faster than the throttle are not all sent on")
    func framesAreThrottled() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        for byte in stride(from: UInt8(0x10), through: 0x60, by: 0x10) {
            bed.store.livePreview = Self.frame(byte)
            try await Task.sleep(for: .milliseconds(15))
        }
        _ = try await phone.waitFor { (try? phone.previews())?.first }
        try await Task.sleep(for: .milliseconds(200))

        let sent = try phone.previews().count
        #expect(sent >= 1)
        #expect(sent < 6, "six frames inside a third of a second are not six messages")
        await bed.shutdown()
    }

    @Test("a run that ends stops the frames without clearing what was sent")
    func clearingThePreviewSendsNothing() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        bed.store.livePreview = Self.frame(0x70)
        _ = try await phone.waitFor { (try? phone.previews())?.first }
        let sent = try phone.previews().count

        bed.store.livePreview = nil
        try await Task.sleep(for: .milliseconds(150))

        #expect(try phone.previews().count == sent)
        await bed.shutdown()
    }
}
