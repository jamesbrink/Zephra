import Foundation
import MLX
import Testing

@testable import ZephraMLX

/// Decoding in tiles against decoding in one piece. The stand-in decoder here is an upsample,
/// which is what the last stages of a real one amount to, so the two results can be compared
/// directly rather than approximately.
@Suite("Tiled decode")
struct TiledDecodeTests {
    @Test("a tiled decode is the shape and near enough the values of an untiled one")
    func matchesTheUntiledDecode() {
        let latents = Self.latent(height: 32, width: 32)
        let exact = Self.upsample(latents)
        let tiled = TiledDecode.run(latents, tile: 16, scale: 8, decode: Self.upsample)
        MLX.eval(exact, tiled)

        #expect(tiled.shape == exact.shape)
        let difference = MLX.abs(tiled - exact).max().item(Float.self)
        #expect(
            difference < 1e-6,
            "a nearest-neighbour decoder gives every tile the same pixels in the overlap, so the cross-fade has nothing to blend and the result is exact"
        )
    }

    @Test("a tile at least as large as the latent decodes it in one piece")
    func oneTileIsTheWholeImage() {
        let latents = Self.latent(height: 8, width: 8)
        let tiled = TiledDecode.run(latents, tile: 16, scale: 8, decode: Self.upsample)
        MLX.eval(tiled)
        #expect(tiled.shape == [1, 64, 64, 3])
    }

    @Test("a latent the stride does not divide still comes back whole")
    func handlesARaggedLastTile() {
        // 20 cells on a stride of 12 leaves a final tile of 8, which is where an off-by-one in
        // the clipping shows up as a short or a doubled edge.
        let latents = Self.latent(height: 20, width: 20)
        let tiled = TiledDecode.run(latents, tile: 16, scale: 8, decode: Self.upsample)
        MLX.eval(tiled)
        #expect(tiled.shape == [1, 160, 160, 3])
    }

    @Test("a tile edge that is not a multiple of four still comes back the size of the image")
    func handlesATileWithARaggedQuarter() {
        // 18 cells stride by 13; keeping 14 cells' worth of pixels per tile instead would
        // return 8 more pixels per seam than the image has.
        let latents = Self.latent(height: 40, width: 40)
        let exact = Self.upsample(latents)
        let tiled = TiledDecode.run(latents, tile: 18, scale: 8, decode: Self.upsample)
        MLX.eval(exact, tiled)
        #expect(tiled.shape == exact.shape)
        #expect(MLX.abs(tiled - exact).max().item(Float.self) < 1e-6)
    }

    /// A smoothly varying latent, so a seam shows up as a difference rather than as noise.
    private static func latent(height: Int, width: Int) -> MLXArray {
        let rows = MLXArray(0..<height, [1, height, 1, 1]).asType(.float32) / Float(height)
        let columns = MLXArray(0..<width, [1, 1, width, 1]).asType(.float32) / Float(width)
        return MLX.broadcast(rows + columns, to: [1, height, width, 4])
    }

    /// A stand-in decoder: nearest-neighbour upsample by 8, four channels down to three.
    private static func upsample(_ latents: MLXArray) -> MLXArray {
        let (height, width) = (latents.dim(1), latents.dim(2))
        let three = latents[0..., 0..., 0..., 0..<3]
        return MLX.broadcast(
            three.reshaped([1, height, 1, width, 1, 3]), to: [1, height, 8, width, 8, 3]
        )
        .reshaped([1, height * 8, width * 8, 3])
    }
}
