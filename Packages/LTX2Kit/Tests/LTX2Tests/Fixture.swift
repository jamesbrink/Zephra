import Foundation
import MLX
import Testing

/// Tensors dumped from the reference implementation, loaded by name.
///
/// Anything here is a claim about what `diffusers` or `transformers` does. A test that loads a
/// fixture is checking this port against that, rather than against its own idea of the
/// architecture.
enum Fixture {
    /// The tensors in one fixture file.
    static func load(_ name: String) throws -> [String: MLXArray] {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/\(name).safetensors"),
            "the fixture bundle is missing")
        return try MLX.loadArrays(url: url)
    }

    /// The largest absolute difference between two tensors, as a Float.
    static func maxAbsoluteDifference(_ a: MLXArray, _ b: MLXArray) -> Float {
        MLX.max(MLX.abs(a.asType(.float32) - b.asType(.float32))).item(Float.self)
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
}
