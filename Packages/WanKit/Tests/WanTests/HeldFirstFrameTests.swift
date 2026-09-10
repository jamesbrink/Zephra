import Foundation
import MLX
import Testing

@testable import Wan

@Suite("a held first frame")
struct HeldFirstFrameTests {
    static let layout = WanLatentLayout(frames: 3, height: 4, width: 6)
    static var held: WanHeldFirstFrame {
        WanHeldFirstFrame(latent: MLXArray.ones([1, 48, 1, 4, 6]) * 7, layout: layout)
    }

    @Test("the mask is zero over the first latent frame and one everywhere after it")
    func mask() {
        #expect(Self.held.mask.shape == [1, 1, 3, 4, 6])
        #expect(Self.held.mask[0, 0, 0].sum().item(Float.self) == 0)
        #expect(Self.held.mask[0, 0, 1...].sum().item(Float.self) == Float(2 * 4 * 6))
    }

    @Test("imposing puts the picture over the first frame and leaves the rest of the sample")
    func imposed() {
        let sample = MLXArray.ones([1, 48, 3, 4, 6]) * 2
        let imposed = Self.held.imposed(on: sample)
        #expect(imposed[0, 0, 0].mean().item(Float.self) == 7)
        #expect(imposed[0, 0, 1].mean().item(Float.self) == 2)
        #expect(imposed[0, 47, 2].mean().item(Float.self) == 2)
    }

    @Test("the tokens over the held frame are told timestep zero, the rest the step's")
    func timesteps() {
        let timesteps = Self.held.timesteps(757)
        // Every other cell: 2 rows of 3 a frame, 3 frames.
        #expect(timesteps.shape == [1, 18])
        let values = timesteps[0].asArray(Float.self)
        #expect(values.prefix(6).allSatisfy { $0 == 0 })
        #expect(values.dropFirst(6).allSatisfy { $0 == 757 })
    }
}
