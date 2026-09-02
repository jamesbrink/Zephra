/// How a model's measured peak memory lands against one Mac's working-set budget.
///
/// The question a picker actually wants answered is "will this page at the default size", and
/// that is decided by peak — resident weights plus the VAE decode's transient — not by resident
/// memory alone. Tiling the decode is the lever that changes the answer, so it gets its own case.
public enum MemoryFit: Hashable, Sendable {
    /// Runs at its default size with the exact, untiled decode.
    case fits
    /// Runs at its default size only with the tiled decode; untiled it would page.
    case fitsTiled
    /// Pages at its default size even tiled. `neededBytes` is the physical memory that would
    /// clear the budget, so it can be shown as "Needs N GB".
    case tight(neededBytes: Int64)

    /// The share of physical memory one generation may occupy before the Mac starts paging.
    ///
    /// Not one: the window server, the browser the prompt was written in and macOS itself are
    /// all still resident. Four fifths is what the measured peaks say a Mac survives — a 32 GB
    /// machine holds the 8-bit model's 23.5 GB peak, a 24 GB machine does not.
    public static let workingSetFraction = 0.8

    /// Bytes one generation may occupy on a Mac with this much RAM.
    public static func budget(physicalMemory: UInt64) -> Double {
        Double(physicalMemory) * workingSetFraction
    }

    /// Where `descriptor` lands on a Mac with `physicalMemory` bytes of RAM.
    public init(descriptor: ModelDescriptor, physicalMemory: UInt64) {
        let budget = MemoryFit.budget(physicalMemory: physicalMemory)
        if Double(descriptor.peakBytes) <= budget {
            self = .fits
        } else if Double(descriptor.tiledPeakBytes) <= budget {
            self = .fitsTiled
        } else {
            let needed = Double(descriptor.tiledPeakBytes) / MemoryFit.workingSetFraction
            self = .tight(neededBytes: Int64(needed.rounded(.up)))
        }
    }

    /// Whether the model runs at its default size at all, tiling allowed.
    public var runsAtDefaultSize: Bool {
        switch self {
        case .fits, .fitsTiled: true
        case .tight: false
        }
    }

    /// Whether reaching the default size depends on the tiled decode.
    public var requiresTiling: Bool { self == .fitsTiled }
}
