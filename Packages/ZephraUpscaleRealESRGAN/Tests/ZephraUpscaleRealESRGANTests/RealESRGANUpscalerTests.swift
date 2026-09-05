import Foundation
import MLX
import Testing
import ZephraCore

@testable import ZephraUpscaleRealESRGAN

/// The seam end to end: PNG bytes in, PNG bytes out, with the bundled checkpoint.
///
/// Each test requires the bundled resource rather than being disabled without it: the weights
/// are a package resource that is always copied, so a missing file is a packaging break the
/// suite must fail on, not a Mac with nothing on it.
@Suite("The upscaler enlarges a picture, reports its tiles, and stops when asked")
struct RealESRGANUpscalerTests {
    static func size(of png: Data) throws -> [Int] {
        try UpscalePixelBuffer.pixels(from: png).shape
    }

    @Test("a picture comes back four times larger")
    func enlargesByFour() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let upscaler = RealESRGANUpscaler()

        let enlarged = try await upscaler.upscale(
            try Fixture.png(edge: 24), UpscaleRequest(factor: 4)) { _ in }

        #expect(try Self.size(of: enlarged) == [1, 96, 96, 3])
    }

    @Test("a 2x request comes back half of the 4x one")
    func enlargesByTwo() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let upscaler = RealESRGANUpscaler()

        let enlarged = try await upscaler.upscale(
            try Fixture.png(edge: 24), UpscaleRequest(factor: 2)) { _ in }

        #expect(try Self.size(of: enlarged) == [1, 48, 48, 3])
    }

    @Test("the last progress event says every tile is done")
    func reportsAFinalEvent() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let upscaler = RealESRGANUpscaler()
        let events = Reports()

        _ = try await upscaler.upscale(try Fixture.png(edge: 24), UpscaleRequest(factor: 4)) {
            events.append($0)
        }

        let last = try #require(events.all.last)
        #expect(last.completedTiles == last.totalTiles)
        #expect(last.fraction == 1)
    }

    @Test("a factor this network does not make is refused")
    func refusesOtherFactors() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let upscaler = RealESRGANUpscaler()

        await #expect(throws: UpscaleError.self) {
            _ = try await upscaler.upscale(try Fixture.png(edge: 8), UpscaleRequest(factor: 3)) {
                _ in
            }
        }
    }

    @Test("a cancelled upscale throws instead of returning bytes")
    func cancellationThrows() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let png = try Fixture.png(edge: 24)
        // A gate rather than a bare `Task { }` and a hopeful `cancel()`: the task is held at
        // its first suspension until after the cancel, so which of the two lands first is not
        // a race the test can lose.
        let gate = AsyncStream<Void>.makeStream()
        let task = Task { () -> Data in
            var opening = gate.stream.makeAsyncIterator()
            _ = await opening.next()
            return try await RealESRGANUpscaler().upscale(png, UpscaleRequest(factor: 4)) { _ in }
        }
        task.cancel()
        gate.continuation.yield(())
        gate.continuation.finish()

        await #expect(throws: UpscaleError.cancelled) { try await task.value }
    }

    @Test("unloading and asking again reads the weights afresh")
    func reloadsAfterUnloading() async throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let upscaler = RealESRGANUpscaler()
        let png = try Fixture.png(edge: 16)

        _ = try await upscaler.upscale(png, UpscaleRequest(factor: 4)) { _ in }
        upscaler.unload()
        let second = try await upscaler.upscale(png, UpscaleRequest(factor: 4)) { _ in }

        #expect(try Self.size(of: second) == [1, 64, 64, 3])
    }
}
