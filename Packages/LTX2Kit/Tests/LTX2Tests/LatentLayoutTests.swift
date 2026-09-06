import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the latent layout")
struct LatentLayoutTests {
    @Test("a clip's frames and size become latent cells on the autoencoder's ladder")
    func fromPixels() {
        let layout = LTX2LatentLayout(pixelFrames: 49, pixelWidth: 768, pixelHeight: 512)
        #expect(layout.frames == 7)
        #expect(layout.height == 16)
        #expect(layout.width == 24)
        #expect(layout.tokens == 7 * 16 * 24)
        #expect(layout.pixelFrames == 49)
        #expect(layout.latentShape == [1, 128, 7, 16, 24])
        #expect(layout.firstFrameTokens == 16 * 24)
        // A single picture is one latent frame.
        #expect(LTX2LatentLayout(pixelFrames: 1, pixelWidth: 512, pixelHeight: 288).frames == 1)
    }

    @Test("packing walks frames, then rows, then columns, and unpacking undoes it")
    func packing() {
        let layout = LTX2LatentLayout(frames: 2, height: 2, width: 3)
        let latent = MLXArray(0..<(2 * 4 * 2 * 2 * 3)).reshaped([2, 4, 2, 2, 3]).asType(.float32)
        let tokens = layout.pack(latent)
        #expect(tokens.shape == [2, 12, 4])
        // Token 0 is cell (0, 0, 0): channels 0..3 at stride frames*height*width.
        #expect(tokens[0, 0].asArray(Float.self) == [0, 12, 24, 36])
        // Token 1 is the next column of the same row.
        #expect(tokens[0, 1].asArray(Float.self) == [1, 13, 25, 37])
        // Token 3 is the second row.
        #expect(tokens[0, 3].asArray(Float.self) == [3, 15, 27, 39])
        #expect(MLX.arrayEqual(layout.unpack(tokens), latent).item(Bool.self))
    }
}
