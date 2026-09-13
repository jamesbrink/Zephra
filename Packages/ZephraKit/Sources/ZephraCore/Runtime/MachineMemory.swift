/// What the whole Mac has, and what of it is going spare right now.
///
/// The GPU's working set says what a model *may* hold; this says what the machine can actually
/// find for it this minute. The two are different questions, and only the second one catches a
/// Mac with a browser, a compiler and Zephra's own last model still on it. Reading it is the
/// app's job (`HostMachineMemory`), so this layer stays free of any host call and testable.
public struct MachineMemory: Hashable, Sendable {
    /// Bytes of RAM in the machine.
    public let physicalBytes: Int64

    /// Bytes a new allocation could take without paging: physical memory less what is wired,
    /// compressed and held internally, with purgeable pages counted back as free, since the
    /// kernel hands those back on demand.
    public let availableBytes: Int64

    public init(physicalBytes: Int64, availableBytes: Int64) {
        self.physicalBytes = physicalBytes
        self.availableBytes = availableBytes
    }

    /// The reading as a fraction of the machine, for a log line.
    public var availableFraction: Double {
        physicalBytes > 0 ? Double(availableBytes) / Double(physicalBytes) : 0
    }
}
