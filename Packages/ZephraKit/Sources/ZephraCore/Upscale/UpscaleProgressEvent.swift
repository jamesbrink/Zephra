/// One progress update from an upscale, which runs the network over the picture in tiles.
public struct UpscaleProgressEvent: Hashable, Sendable {
    /// How many tiles have been through the network.
    public let completedTiles: Int
    /// How many tiles the picture was cut into.
    public let totalTiles: Int

    /// Creates an upscale update.
    public init(completedTiles: Int, totalTiles: Int) {
        self.completedTiles = completedTiles
        self.totalTiles = totalTiles
    }

    /// Overall completion from 0 to 1. Every tile costs the same, so a count is a fraction.
    public var fraction: Double {
        Double(completedTiles) / Double(max(1, totalTiles))
    }
}
