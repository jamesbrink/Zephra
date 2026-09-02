/// One progress update from a model download.
public struct DownloadProgressEvent: Hashable, Sendable {
    /// How many files have finished transferring.
    public let completedFiles: Int
    /// How many files the download covers in total.
    public let totalFiles: Int
    /// Overall completion from 0 to 1, weighted by bytes rather than by file count.
    public let fraction: Double
    /// Current transfer rate, absent until enough has moved to measure one.
    public let bytesPerSecond: Double?

    /// Creates a download update.
    public init(
        completedFiles: Int,
        totalFiles: Int,
        fraction: Double,
        bytesPerSecond: Double? = nil
    ) {
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.fraction = fraction
        self.bytesPerSecond = bytesPerSecond
    }
}
