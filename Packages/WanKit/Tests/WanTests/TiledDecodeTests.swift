import Foundation
import MLX
import Testing

@testable import Wan

@Suite("the decoder in spatial tiles")
struct TiledDecodeTests {
    @Test("a tiled decode has the clip's shape, and a tile as large as the latent is the plain decode")
    func shapeAndIdentity() throws {
        let fixture = try Fixture.load("vae_decoder")
        let autoencoder = try VAEEncoderParityTests.loaded(fixture)
        let latent = try #require(fixture["in.latent"])  // [1, 4, 2, 4, 4]
        let whole = autoencoder.decode(latent)
        let same = autoencoder.decode(latent, tile: 4)
        #expect(Fixture.maxAbsoluteDifference(whole, same) == 0)
        let tiled = autoencoder.decode(latent, tile: 2)
        #expect(tiled.shape == whole.shape)
        #expect(tiled.max().item(Float.self) <= 1)
    }
}
