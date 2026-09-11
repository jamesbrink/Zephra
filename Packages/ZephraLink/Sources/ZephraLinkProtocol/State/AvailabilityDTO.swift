import ZephraCore

/// Whether a model's weights are on the Mac, and what having them would cost.
///
/// The label travels with the case. It is one sentence the Mac already writes for its own
/// picker, and sending it means the phone shows the same words rather than a second rendering
/// of the same five cases that has to be kept in step.
public struct AvailabilityDTO: Codable, Hashable, Sendable {
    /// Which of `ModelAvailability`'s cases this is.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case available, needsDownload, needsDownloadAndBuild, needsBuild, missing
    }

    /// The case.
    public var kind: Kind
    /// Roughly how many bytes choosing it would transfer, where it would transfer any.
    public var bytes: Int64?
    /// Why it cannot be got, or what it costs beyond a download; nil where there is nothing
    /// to add.
    public var reason: String?
    /// The short line a picker shows under the model's name.
    public var label: String
    /// Whether choosing it would start a download.
    public var needsNetwork: Bool
    /// Whether it can be loaded at all, now or after a transfer.
    public var isObtainable: Bool

    /// Creates an availability from explicit facts.
    public init(
        kind: Kind, bytes: Int64?, reason: String?, label: String, needsNetwork: Bool,
        isObtainable: Bool
    ) {
        self.kind = kind
        self.bytes = bytes
        self.reason = reason
        self.label = label
        self.needsNetwork = needsNetwork
        self.isObtainable = isObtainable
    }

    /// The wire form of one availability answer.
    public init(_ availability: ModelAvailability) {
        switch availability {
        case .available: (kind, bytes) = (.available, nil)
        case .needsDownload(let count): (kind, bytes) = (.needsDownload, count)
        case .needsDownloadAndBuild(let count): (kind, bytes) = (.needsDownloadAndBuild, count)
        case .needsBuild: (kind, bytes) = (.needsBuild, nil)
        case .missing: (kind, bytes) = (.missing, nil)
        }
        reason = availability.reason
        label = availability.label
        needsNetwork = availability.needsNetwork
        isObtainable = availability.isObtainable
    }
}
