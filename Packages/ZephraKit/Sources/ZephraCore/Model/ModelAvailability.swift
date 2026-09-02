/// Whether a model's weights can be loaded right now, answered without touching the network.
///
/// This is what lets a picker say "13.3 GB download" beside a model instead of finding out by
/// starting the transfer.
public enum ModelAvailability: Hashable, Sendable {
    /// The weights are on this Mac already and look complete.
    case available
    /// Nothing usable is cached; loading will transfer roughly this many bytes first.
    case needsDownload(bytes: Int64)
    /// The weights cannot be got from here at all, for the reason given. A local directory that
    /// was never built is the case this exists for: there is nowhere to download it from.
    case missing(reason: String)

    /// Whether choosing this model would start a download.
    public var needsNetwork: Bool {
        if case .needsDownload = self { return true }
        return false
    }

    /// Whether the model can be loaded, now or after a download.
    public var isObtainable: Bool {
        if case .missing = self { return false }
        return true
    }

    /// Why the model cannot be obtained, or nil when it can. Long enough for a tooltip.
    public var reason: String? {
        if case .missing(let reason) = self { return reason }
        return nil
    }

    /// The short line a picker shows under the model's name. The full explanation behind
    /// `.missing` stays in `reason`, where a tooltip can show it.
    public var label: String {
        switch self {
        case .available: "Downloaded"
        case .needsDownload(let bytes): "\(ByteCount.gigabytes(bytes)) download"
        case .missing: "Not built yet"
        }
    }
}
