/// Turns a preference and a machine into the tile edge the VAE decode should run at.
///
/// A value type with no state of its own so the decision is testable without a GPU: give it a
/// mode and a memory size, ask it about a model, and it answers with a latent tile edge or nil
/// for the exact untiled decode.
public struct VAETilingPolicy: Hashable, Sendable {
    /// The latent-space tile edge the app asks for when it tiles. 64 latent cells is a
    /// 512-pixel tile, which is what the 5437 MB transient in `ModelDescriptor.tiledPeakBytes`
    /// was measured at.
    public static let latentTileEdge = 64

    /// What the user chose.
    public let mode: VAETilingMode
    /// Bytes of RAM in the machine, as `ProcessInfo.physicalMemory` reports them.
    public let physicalMemory: UInt64

    public init(mode: VAETilingMode, physicalMemory: UInt64) {
        self.mode = mode
        self.physicalMemory = physicalMemory
    }

    /// The tile edge to run `descriptor` at, or nil to decode untiled.
    ///
    /// Under `automatic` the test is the model's untiled peak against the working-set budget:
    /// a 48 GB Mac holds the 8-bit model exactly and never tiles, a 24 GB one tiles for it and
    /// not for the 4-bit variant, and a 16 GB one tiles for everything it is offered. A nil
    /// descriptor — no model chosen yet — decodes untiled, since nothing is about to be decoded.
    public func tileSize(for descriptor: ModelDescriptor?) -> Int? {
        switch mode {
        case .never:
            nil
        case .always:
            Self.latentTileEdge
        case .automatic:
            descriptor.flatMap { model in
                Double(model.peakBytes) > MemoryFit.budget(physicalMemory: physicalMemory)
                    ? Self.latentTileEdge
                    : nil
            }
        }
    }
}
