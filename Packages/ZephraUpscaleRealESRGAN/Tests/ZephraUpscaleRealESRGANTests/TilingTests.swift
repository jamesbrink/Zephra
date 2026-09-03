import Foundation
import MLX
import Testing
import ZephraMLX

@testable import ZephraUpscaleRealESRGAN

@Suite("Tiling reassembles the picture, and halving it is an exact box mean")
struct TilingTests {
    @Test("tiling reassembles what the untiled network produced")
    func tilingReassembles() throws {
        let fixture = try Fixture.load("srvgg_x4")
        let model = try Fixture.network(fixture, scale: 4)
        // Wider than the 512 tile, so the stride of 384 really cuts it into four.
        let image = Fixture.smooth(edge: 576)
        #expect(TiledUpscale.tileCount(height: 576, width: 576) == 4)

        let whole = model(image)
        let tiled = try TiledUpscale.run(image, through: model)

        #expect(tiled.shape == whole.shape)
        // A tolerance rather than equality: the 128-pixel overlap is far wider than the
        // network's 34-pixel receptive field, so the only place a tile's own zero padding can
        // still be felt is a 34-pixel sliver at the low end of the fade, where the incoming
        // tile carries at most 0.27 of the weight.
        let difference = Fixture.meanAbsoluteDifference(tiled, whole)
        #expect(
            difference < 2.0 / 255.0,
            Comment(rawValue: "tiling moved the pixels by \(difference)"))
    }

    @Test("every tile is reported once, in order, against the same total")
    func everyTileIsReported() throws {
        let fixture = try Fixture.load("srvgg_x4")
        let model = try Fixture.network(fixture, scale: 4)
        var reports: [Int] = []
        var totals: Set<Int> = []

        _ = try TiledUpscale.run(Fixture.smooth(edge: 576), through: model) { completed, total in
            reports.append(completed)
            totals.insert(total)
        }

        #expect(reports == [1, 2, 3, 4])
        #expect(totals == [4])
    }

    @Test("2x is the box mean of 4x")
    func halvingIsABoxMean() {
        // The values name their own coordinates, so a wrong pairing -- rows with rows, or a
        // stride of one -- lands on a different number rather than a nearby one.
        let enlarged = MLXArray((0..<16).map { Float($0) }, [1, 4, 4, 1])

        let halved = BoxDownsample.half(enlarged)

        #expect(halved.shape == [1, 2, 2, 1])
        let expected = MLXArray([2.5, 4.5, 10.5, 12.5] as [Float], [1, 2, 2, 1])
        #expect(Fixture.maxAbsoluteDifference(halved, expected) == 0)
    }
}
