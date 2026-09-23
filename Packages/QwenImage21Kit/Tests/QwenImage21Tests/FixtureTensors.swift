import Foundation
import MLX
import Testing

/// Reading the shapes a transformer fixture stores that are not tensors of floats: masks and
/// ids go down as `int32`, and a module's weights go down under a prefix beside its own inputs
/// and outputs.
///
/// Kept beside the transformer's suites rather than in `Fixture` so the components being
/// written in parallel do not each edit one file.
extension Fixture {
    /// One `int32` tensor as Swift integers.
    static func ints(_ fixture: [String: MLXArray], _ name: String) throws -> [Int] {
        try #require(fixture[name], "no \(name) in the fixture").asArray(Int32.self).map(Int.init)
    }

    /// One `int32` tensor as flags, which is how a mask crosses.
    static func flags(_ fixture: [String: MLXArray], _ name: String) throws -> [Bool] {
        try ints(fixture, name).map { $0 != 0 }
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
