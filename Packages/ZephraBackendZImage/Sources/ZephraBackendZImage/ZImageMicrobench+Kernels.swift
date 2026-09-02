import Foundation
import MLX

/// The rotary formulations the microbench compares, plus its timing, reporting and noise
/// helpers. Split from `ZImageMicrobench` only to keep both files small.
extension ZImageMicrobench {
    /// The vendored formulation: reshape to pairs, two strided slices, four multiplies,
    /// `stacked`, reshape back.
    static func stackedRotary(_ x: MLXArray, _ cos: MLXArray, _ sin: MLXArray) -> MLXArray {
        let shape = x.shape
        let paired = x.reshaped(Array(shape.dropLast()) + [shape.last! / 2, 2])
        let real = paired[0..., 0..., 0..., 0..., 0]
        let imag = paired[0..., 0..., 0..., 0..., 1]
        return MLX.stacked([real * cos - imag * sin, real * sin + imag * cos], axis: -1).reshaped(shape)
    }

    /// The candidate replacement: one `concatenated` over the pair axis instead of `stacked`
    /// over a new trailing axis.
    static func splitRotary(_ x: MLXArray, _ cos: MLXArray, _ sin: MLXArray) -> MLXArray {
        let shape = x.shape
        let paired = x.reshaped(Array(shape.dropLast()) + [shape.last! / 2, 2])
        let real = paired[.ellipsis, 0 ..< 1]
        let imag = paired[.ellipsis, 1 ..< 2]
        let c = cos[.ellipsis, .newAxis]
        let s = sin[.ellipsis, .newAxis]
        return MLX.concatenated([real * c - imag * s, real * s + imag * c], axis: -1).reshaped(shape)
    }

    /// Runs `body` once to force kernel compilation, then times `iterations` more.
    static func time(_ iterations: Int, _ body: () -> MLXArray) -> Double {
        MLX.eval(body())
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations {
            MLX.eval(body())
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        return elapsed / Double(iterations)
    }

    static func report(_ label: String, _ seconds: Double) {
        print(String(format: "  %-46@ %8.3f ms", label as NSString, seconds * 1000))
    }
}
