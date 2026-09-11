import ZephraEngine

/// One model transfer, as a row on the phone.
///
/// `ModelDownload` carries the whole `ModelDescriptor` and a progress event; this carries the
/// model's id and the numbers, because a transfer row is a name, a bar and a state.
public struct DownloadDTO: Codable, Hashable, Sendable, Identifiable {
    /// Which of `ModelDownload.Status`'s cases this is.
    public enum Status: String, Codable, Hashable, Sendable, CaseIterable {
        case queued, downloading, paused, completed, cancelled, failed
    }

    /// The request's identity, which is what Pause and Cancel name.
    public var id: String
    /// The model being fetched, as a descriptor identifier.
    public var modelID: String
    /// The model's name as shown.
    public var displayName: String
    /// Where the transfer stands.
    public var status: Status
    /// What went wrong, when the status is a failure.
    public var message: String?
    /// Completion from 0 to 1, weighted by bytes, or nil before anything has moved.
    public var fraction: Double?
    /// Bytes transferred so far.
    public var completedBytes: Int64?
    /// Bytes the transfer covers.
    public var totalBytes: Int64?
    /// Current rate, where one has been measured.
    public var bytesPerSecond: Double?

    /// Creates a transfer row from explicit facts.
    public init(
        id: String, modelID: String, displayName: String, status: Status, message: String? = nil,
        fraction: Double? = nil, completedBytes: Int64? = nil, totalBytes: Int64? = nil,
        bytesPerSecond: Double? = nil
    ) {
        self.id = id
        self.modelID = modelID
        self.displayName = displayName
        self.status = status
        self.message = message
        self.fraction = fraction
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
    }

    /// The wire form of one of the Mac's download requests.
    public init(_ download: ModelDownload) {
        id = download.id
        modelID = download.model.id
        displayName = download.model.displayName
        switch download.status {
        case .queued: (status, message) = (.queued, nil)
        case .downloading: (status, message) = (.downloading, nil)
        case .paused: (status, message) = (.paused, nil)
        case .completed: (status, message) = (.completed, nil)
        case .cancelled: (status, message) = (.cancelled, nil)
        case .failed(let reason): (status, message) = (.failed, reason)
        }
        fraction = download.progress?.fraction
        completedBytes = download.progress?.completedBytes
        totalBytes = download.progress?.totalBytes
        bytesPerSecond = download.progress?.bytesPerSecond
    }
}
