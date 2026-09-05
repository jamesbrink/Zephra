import CoreGraphics
import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage

/// The doll's house `DenoiseLoopTests` drives: the stub model, an exact ladder, and the
/// hand-computable trajectory through it.
extension DenoiseLoopTests {
    /// Answers `k * latents`, counts its calls, and can cancel the task it runs in.
    final class Stub: QwenImageVelocityModel {
        let k: Float
        var calls = 0
        var cancelOnCall: Int?
        init(k: Float, cancelOnCall: Int? = nil) {
            self.k = k
            self.cancelOnCall = cancelOnCall
        }
        func callAsFunction(
            latents: MLXArray, text: MLXArray, timestep: MLXArray,
            frequencies: (image: RotaryFrequencies, text: RotaryFrequencies)
        ) throws -> MLXArray {
            calls += 1
            if calls == cancelOnCall { withUnsafeCurrentTask { $0?.cancel() } }
            return latents * k
        }
    }

    /// A scheduler whose ladder is exact: no dynamic shift, no terminal, so four steps are
    /// 1, 0.75, 0.5, 0.25 and then 0.
    static let scheduler = FlowMatchEulerScheduler(
        configuration: QwenImageSchedulerConfiguration(
            numTrainTimesteps: 1000, shift: 1, useDynamicShifting: false, baseShift: 0.5,
            maxShift: 0.9, baseImageSeqLen: 256, maxImageSeqLen: 8192, shiftTerminal: nil,
            timeShiftType: "exponential"),
        steps: 4, imageSequenceLength: 16)
    /// An 8 by 8 latent of four channels: sixteen 2x2 patches of sixteen channels.
    static let latentSize = (height: 8, width: 8)
    static var frequencies: (image: RotaryFrequencies, text: RotaryFrequencies) {
        QwenImageRotaryEmbedding(theta: 10000, axesDim: [4, 6, 6])
            .frequencies(frames: 1, height: 4, width: 4, textLength: 5)
    }
    static var conditioning: MLXArray { MLXArray.zeros([1, 5, 24]) }

    static func noise() -> MLXArray {
        let values = (0..<(16 * 16)).map { Float($0 % 7) / 7 - 0.5 }
        return MLXArray(values, [1, 16, 16])
    }

    /// The latent after `steps` Euler steps of `k * x` from `start`, entering at `from`.
    static func expected(from start: MLXArray, k: Float, entering from: Int, steps: Int) -> MLXArray {
        var x = start
        for index in from..<steps {
            x = x * (1 + k * Float(scheduler.sigmas[index + 1] - scheduler.sigmas[index]))
        }
        return x
    }

    static func run(
        _ stub: Stub, reference: QwenImageDenoiseLoop.Reference? = nil,
        autoencoder: QwenImageAutoencoder? = nil,
        onProgress: (QwenImageGenerationProgress) -> Void = { _ in },
        onPreview: QwenImagePipeline.PreviewHandler? = nil
    ) throws -> MLXArray {
        try QwenImageDenoiseLoop.run(
            noise: noise(), latentSize: latentSize, reference: reference, scheduler: scheduler,
            transformer: stub, autoencoder: autoencoder ?? (try LatentPreviewTests.autoencoder()),
            conditioning: conditioning, frequencies: frequencies,
            onProgress: onProgress, onPreview: onPreview)
    }

    static func steps(_ events: [QwenImageGenerationProgress]) -> [Int] {
        events.compactMap {
            if case .denoising(let step, _) = $0.stage { step } else { nil }
        }
    }

    /// A solid mid-grey picture `edge` pixels square.
    static func solidImage(edge: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
        return try #require(context.makeImage())
    }
}
