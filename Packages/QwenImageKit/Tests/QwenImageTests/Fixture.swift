import Foundation
import MLX
import Testing

/// Tensors dumped from the reference implementation, loaded by name.
///
/// Anything here is a claim about what `diffusers` does. A test that loads a fixture is checking
/// this port against that, rather than against its own idea of the architecture.
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
}
