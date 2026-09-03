/// What an upscale is asked to do: how many times larger each edge should come back.
///
/// Only 2 and 4 are offered. The network is a 4x one; 2x is the same pass followed by an
/// exact 2x2 box mean, which the interface says nothing about because it changes no decision
/// a person makes.
public struct UpscaleRequest: Hashable, Sendable {
    /// The multiplier for each edge: 2 or 4.
    public let factor: Int

    /// Creates a request for `factor` times each edge.
    public init(factor: Int) {
        self.factor = factor
    }
}
