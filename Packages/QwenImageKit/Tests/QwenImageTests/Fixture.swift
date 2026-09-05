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
        try MLX.loadArrays(url: url("\(name).safetensors"))
    }

    /// A fixture that is not tensors, decoded from `Fixtures/<name>.json`.
    static func json<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) throws
        -> Value
    {
        try JSONDecoder().decode(type, from: Data(contentsOf: url("\(name).json")))
    }

    private static func url(_ file: String) throws -> URL {
        try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/\(file)"),
            "the fixture bundle is missing")
    }

    /// The largest absolute difference between two tensors, as a Float.
    static func maxAbsoluteDifference(_ a: MLXArray, _ b: MLXArray) -> Float {
        MLX.max(MLX.abs(a.asType(.float32) - b.asType(.float32))).item(Float.self)
    }
}
