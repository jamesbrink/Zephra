import Foundation
import ZephraCore

/// One model request shown in Settings. Several requests can share repository bytes.
public struct ModelDownload: Identifiable, Sendable {
    public enum Status: Sendable, Equatable {
        case queued, downloading, paused, completed, cancelled, failed(String)
    }
    public let id: String
    public let model: ModelDescriptor
    public internal(set) var status: Status
    public internal(set) var progress: DownloadProgressEvent?
}
