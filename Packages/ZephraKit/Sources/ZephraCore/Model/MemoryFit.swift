/// How a model's measured peak memory lands against one Mac's working-set budget.
///
/// The question a picker actually wants answered is "will this page at the default size", and
/// that is decided by peak — resident weights plus the VAE decode's transient — not by resident
/// memory alone. Tiling the decode is the lever that changes the answer, so it gets its own
/// case, and streaming the weights from disk is the lever after that.
public enum MemoryFit: Hashable, Sendable {
    /// Runs at its default size with the exact, untiled decode.
    case fits
    /// Runs at its default size only with the tiled decode; untiled it would page.
    case fitsTiled
    /// Runs at its default size only with the weights streamed from disk every step, and the
    /// decode tiled; held resident it would page.
    case fitsStreamed
    /// Pages at its default size even tiled. `neededBytes` is the GPU working set that would
    /// clear the budget, so it can be shown as "Needs N GB".
    case tight(neededBytes: Int64)

    /// Where `descriptor` lands against `budget`.
    public init(descriptor: ModelDescriptor, budget: MemoryBudget) {
        let bytes = budget.bytes
        if Double(descriptor.peakBytes) <= bytes {
            self = .fits
        } else if Double(descriptor.tiledPeakBytes) <= bytes {
            self = .fitsTiled
        } else if descriptor.streamedPeakBytes > 0, Double(descriptor.streamedPeakBytes) <= bytes {
            self = .fitsStreamed
        } else {
            self = .tight(neededBytes: descriptor.tiledPeakBytes)
        }
    }

    /// Where `descriptor` lands on a Mac with `physicalMemory` bytes of RAM whose GPU has not
    /// been asked what it may keep.
    public init(descriptor: ModelDescriptor, physicalMemory: UInt64) {
        self.init(descriptor: descriptor, budget: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// Whether the model runs at its default size at all, tiling and streaming allowed.
    public var runsAtDefaultSize: Bool {
        switch self {
        case .fits, .fitsTiled, .fitsStreamed: true
        case .tight: false
        }
    }

    /// Whether reaching the default size depends on the tiled decode.
    public var requiresTiling: Bool { self == .fitsTiled || self == .fitsStreamed }

    /// Whether reaching the default size depends on streaming the weights from disk.
    public var requiresStreaming: Bool { self == .fitsStreamed }

    /// Whether a `tight` verdict would turn into a fit if the GPU were allowed the whole of
    /// RAM, which is what raising `iogpu.wired_limit_mb` does. The settings row shows the
    /// command only when it would help.
    public static func wouldFitWithWiredLimitRaised(
        _ descriptor: ModelDescriptor, budget: MemoryBudget
    ) -> Bool {
        Double(descriptor.tiledPeakBytes) <= Double(budget.physicalMemory)
    }
}
