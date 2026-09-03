import Foundation
import MLX
import Testing

@testable import ZephraUpscaleRealESRGAN

/// Tensors dumped from the reference architecture by `Tools/dump_reference.py`, loaded by name.
///
/// Anything here is a claim about what torch's `SRVGGNetCompact` does. A test that loads a
/// fixture is checking this port against that, rather than against its own idea of the
/// architecture.
///
/// Every parity tolerance below is against these **float32** tensors. The bundled checkpoint is
/// float16 and is never compared by value -- only by name and shape -- because float16 rounding
/// would swamp a 1e-4 claim and turn a real regression into noise.
enum Fixture {
    /// The doll's house `dump_reference.py` builds: eight features, two body convolutions.
    static func configuration(scale: Int) -> SRVGGNetConfiguration {
        SRVGGNetConfiguration(features: 8, convolutions: 2, scale: scale)
    }

    /// The tensors in one fixture file.
    static func load(_ name: String) throws -> [String: MLXArray] {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/\(name).safetensors"),
            "the fixture bundle is missing")
        return try MLX.loadArrays(url: url)
    }

    /// A network of `scale` with the fixture's weights in it.
    static func network(_ fixture: [String: MLXArray], scale: Int) throws -> SRVGGNet {
        let model = SRVGGNet(configuration(scale: scale))
        try SRVGGNetWeights.load(
            into: model, weights: SRVGGNetWeights.sanitized(weights(fixture, under: "net.")))
        return model
    }

    /// The tensors under `prefix`, with the prefix removed and the fixture's own inputs and
    /// outputs left out, which is what a module's weights look like.
    static func weights(_ fixture: [String: MLXArray], under prefix: String) -> [String: MLXArray] {
        var weights: [String: MLXArray] = [:]
        for (key, value) in fixture where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            guard !name.hasPrefix("in."), !name.hasPrefix("out.") else { continue }
            weights[name] = value
        }
        return weights
    }

    /// A `[N, C, H, W]` fixture read as the `[N, H, W, C]` this port speaks.
    static func channelsLast(_ tensor: MLXArray) -> MLXArray {
        tensor.transposed(0, 2, 3, 1)
    }

    /// A smooth synthetic picture, `[1, edge, edge, 3]` in 0...1.
    ///
    /// Deterministic, and free of the high frequencies that would make a seam a matter of luck:
    /// trained weights are what make real content stationary across a tile boundary, and the
    /// doll's house has random ones, so the content has to be.
    static func smooth(edge: Int) -> MLXArray {
        var values = [Float](repeating: 0, count: edge * edge * 3)
        for row in 0..<edge {
            for column in 0..<edge {
                for channel in 0..<3 {
                    let phase = Float(channel) * 0.7
                    values[(row * edge + column) * 3 + channel] =
                        0.5
                        + 0.4 * sin(Float(column) / 37 + phase) * cos(Float(row) / 29 + phase)
                }
            }
        }
        return MLXArray(values, [1, edge, edge, 3])
    }

    /// That picture as PNG bytes, which is what the seam takes.
    static func png(edge: Int) throws -> Data {
        try UpscalePixelBuffer.png(from: smooth(edge: edge))
    }

    /// The largest absolute difference between two tensors, as a Float.
    static func maxAbsoluteDifference(_ a: MLXArray, _ b: MLXArray) -> Float {
        MLX.max(MLX.abs(a.asType(.float32) - b.asType(.float32))).item(Float.self)
    }

    /// The mean absolute difference between two tensors, as a Float.
    static func meanAbsoluteDifference(_ a: MLXArray, _ b: MLXArray) -> Float {
        MLX.mean(MLX.abs(a.asType(.float32) - b.asType(.float32))).item(Float.self)
    }
}
