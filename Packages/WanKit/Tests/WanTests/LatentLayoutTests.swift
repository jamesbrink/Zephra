import Foundation
import MLX
import Testing

@testable import Wan

@Suite("the latent layout")
struct LatentLayoutTests {
    @Test("a clip's frames and size become latent cells on the autoencoder's ladder, and tokens on the patch")
    func fromPixels() {
        let layout = WanLatentLayout(pixelFrames: 49, pixelWidth: 832, pixelHeight: 480)
        #expect(layout.frames == 13)
        #expect(layout.height == 30)
        #expect(layout.width == 52)
        // Two cells by two make a token: 15 rows of 26 a frame.
        #expect(layout.tokens == 13 * 15 * 26)
        #expect(layout.firstFrameTokens == 15 * 26)
        #expect(layout.pixelFrames == 49)
        #expect(layout.latentShape == [1, 48, 13, 30, 52])
        #expect(WanLatentLayout.pixelAlignment == 32)
        // A single picture is one latent frame.
        #expect(WanLatentLayout(pixelFrames: 1, pixelWidth: 512, pixelHeight: 288).frames == 1)
    }
}
