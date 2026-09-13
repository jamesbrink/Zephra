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
    /// Pages at its default size on every lever this family has. `neededBytes` is the GPU
    /// working set that would clear the budget — the leanest figure the model can be run at,
    /// streamed where the family streams — so it can be shown as "Needs N GB".
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
            self = .tight(neededBytes: descriptor.leanestPeakBytes)
        }
    }

    /// Where `descriptor` lands on a Mac with `physicalMemory` bytes of RAM whose GPU has not
    /// been asked what it may keep.
    public init(descriptor: ModelDescriptor, physicalMemory: UInt64) {
        self.init(descriptor: descriptor, budget: MemoryBudget(physicalMemory: physicalMemory))
    }

    /// Whether this Mac may choose the model at all, tiling and streaming allowed.
    ///
    /// The gate, not a note: a model this Mac cannot hold is greyed wherever it is listed and
    /// is never loaded, never downloaded, and never queued for from a phone.
    public var isSelectable: Bool {
        switch self {
        case .fits, .fitsTiled, .fitsStreamed: true
        case .tight: false
        }
    }

    /// Whether the model runs with its weights held in memory, tiled or not. The opposite of
    /// this is what `Automatic` streams: a model that does not fit resident is streamed rather
    /// than loaded resident and left to page.
    public var fitsResident: Bool { self == .fits || self == .fitsTiled }

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
        Double(descriptor.leanestPeakBytes) <= Double(budget.physicalMemory)
    }
}
