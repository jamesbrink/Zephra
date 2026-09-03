/// Whether a model's weights can be loaded right now, answered without touching the network.
///
/// This is what lets a picker say "13.3 GB download" beside a model instead of finding out by
/// starting the transfer.
public enum ModelAvailability: Hashable, Sendable {
    /// The weights are on this Mac already and look complete.
    case available
    /// Nothing usable is cached; loading will transfer roughly this many bytes first.
    case needsDownload(bytes: Int64)
    /// Nothing is cached, and the release is not what gets loaded: choosing this transfers
    /// roughly this many bytes and then spends a while packing them into the variant this Mac
    /// runs. The two costs are named apart because they are paid apart.
    case needsDownloadAndBuild(bytes: Int64)
    /// The release is on this Mac but the packed variant is not: a build, and no network.
    case needsBuild
    /// The weights cannot be got from here at all, for the reason given. A local directory that
    /// was never built is the case this exists for: there is nowhere to download it from.
    case missing(reason: String)

    /// Whether choosing this model would start a download.
    public var needsNetwork: Bool {
        switch self {
        case .needsDownload, .needsDownloadAndBuild: true
        case .available, .needsBuild, .missing: false
        }
    }

    /// Whether the model can be loaded, now or after a download.
    public var isObtainable: Bool {
        if case .missing = self { return false }
        return true
    }

    /// Why the model cannot be obtained, or what choosing it will cost beyond a download, or nil
    /// when there is nothing to add. Long enough for a tooltip.
    public var reason: String? {
        switch self {
        case .missing(let reason): reason
        case .needsBuild, .needsDownloadAndBuild:
            "Zephra packs this model into the variant this Mac runs the first time it is loaded."
        case .available, .needsDownload: nil
        }
    }

    /// The short line a picker shows under the model's name. The full explanation behind
    /// `.missing` stays in `reason`, where a tooltip can show it.
    public var label: String {
        switch self {
        case .available: "Downloaded"
        case .needsDownload(let bytes): "\(ByteCount.gigabytes(bytes)) download"
        case .needsDownloadAndBuild(let bytes): "\(ByteCount.gigabytes(bytes)) download, then built"
        case .needsBuild: "Builds on first load"
        case .missing: "Not built yet"
        }
    }
}
