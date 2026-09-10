import Foundation
import MLX

/// The timestep of every token in one forward, as the few distinct values it takes and which
/// of them each token has.
///
/// The reference embeds the timestep once per token: `timestep` is `[batch, tokens]`, it is
/// flattened, run through the condition embedder, and unflattened, so a 73,000-token clip
/// runs the embedding MLP 73,000 times and holds `[1, 73000, 6, 3072]` across all thirty
/// blocks. The field takes a different route to the same numbers: a token's rows depend on
/// its timestep alone, and a run has one or two of those (the step's, and 0 over a held first
/// frame), so the embedder runs once per distinct value and each block gathers its rows per
/// token on the way in, where they are transient. Reading the values back to the CPU is what
/// makes them countable; the array is one number per token and the read is one small copy.
struct WanTimestepField {
    /// The distinct timesteps, `[count]`, float32, in order of first appearance.
    let values: MLXArray
    /// Which of `values` each token has, `[batch, tokens]`, or `[batch, 1]` when every token
    /// of every batch element is at one timestep, so the gathered rows broadcast.
    let index: MLXArray

    /// - Parameter timesteps: `[batch]`, one timestep for all of a batch element's tokens, or
    ///   `[batch, tokens]`, one per token, in the model's 0 to 1000 units.
    init(_ timesteps: MLXArray) {
        let batch = timesteps.shape[0]
        let tokens = timesteps.ndim == 1 ? 1 : timesteps.shape[1]
        let flat = timesteps.asType(.float32).reshaped([-1]).asArray(Float.self)
        var distinct: [Float] = []
        var positions: [Float: Int32] = [:]
        var indices: [Int32] = []
        indices.reserveCapacity(flat.count)
        for value in flat {
            if let position = positions[value] {
                indices.append(position)
            } else {
                positions[value] = Int32(distinct.count)
                indices.append(Int32(distinct.count))
                distinct.append(value)
            }
        }
        values = MLXArray(distinct)
        let uniform = (0..<batch).allSatisfy { element in
            let row = indices[(element * tokens)..<((element + 1) * tokens)]
            return row.allSatisfy { $0 == row.first }
        }
        index =
            uniform
            ? MLXArray((0..<batch).map { indices[$0 * tokens] }, [batch, 1])
            : MLXArray(indices, [batch, tokens])
    }

    /// `rows`, `[count, ...]`, one entry per distinct timestep, gathered per token as
    /// `[batch, tokens, ...]` (or `[batch, 1, ...]` for a uniform field).
    func perToken(_ rows: MLXArray) -> MLXArray {
        MLX.take(rows, index.reshaped([-1]), axis: 0).reshaped(index.shape + Array(rows.shape.dropFirst()))
    }
}
