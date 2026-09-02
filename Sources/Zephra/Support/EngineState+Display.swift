import Foundation
import ZephraCore
import ZephraEngine

/// The words the canvas and the window subtitle use for each engine state.
///
/// Copy rules: sentence case, active verbs, the same verb through the flow, and every
/// failure names a cause and a remedy. Nothing here apologises.
extension EngineState {
    /// The window subtitle: the state in a word, plus the measurement that matters while it runs.
    var subtitle: String {
        switch self {
        case .ready: "Ready"
        case .failed: "Failed"
        default:
            if let detail {
                "\(statusLabel) · \(detail.prefix(1).lowercased() + detail.dropFirst())"
            } else {
                statusLabel
            }
        }
    }

    /// The state in a word or two.
    var statusLabel: String {
        switch self {
        case .idle: "Not loaded"
        case .checkingModel: "Checking model"
        case .downloading: "Downloading"
        case .loading: "Preparing"
        case .warmingUp: "Warming up"
        case .ready: "Ready"
        case .generating: "Generating"
        case .cancelling: "Stopping"
        case .failed: "Failed"
        }
    }

    /// The headline the canvas shows, or nil when the canvas needs no headline.
    func title(for descriptor: ModelDescriptor) -> String? {
        switch self {
        case .idle:
            "\(descriptor.displayName) isn't loaded yet."
        case .checkingModel, .loading:
            "Preparing model…"
        case .downloading:
            "\(descriptor.displayName) needs a one-time \(Self.gigabytes(descriptor.downloadBytes)) download."
        case .warmingUp:
            "Warming up…"
        case .cancelling:
            "Stopping after this step…"
        case .failed(let error):
            error.message
        case .ready, .generating:
            nil
        }
    }

    /// The second line under the headline: file counts while downloading, pace while generating.
    var detail: String? {
        switch self {
        case .downloading(let event):
            Self.downloadDetail(event)
        case .generating(let event):
            Self.generationDetail(event)
        default:
            nil
        }
    }

    /// Whether the detail line is a measurement, which is set in a monospaced face.
    var detailIsMeasurement: Bool {
        if case .generating = self { return true }
        if case .downloading = self { return true }
        return false
    }

    /// The step the diffusion loop is on, and how many there are, while one is running.
    var denoisingProgress: (step: Int, total: Int)? {
        guard case .generating(let event) = self,
              case .denoising(let step, let total) = event.phase
        else { return nil }
        return (step, total)
    }

    private static func downloadDetail(_ event: DownloadProgressEvent) -> String {
        var parts = ["File \(event.completedFiles) of \(event.totalFiles)"]
        if let rate = event.bytesPerSecond, rate > 0 {
            parts.append("\(Int64(rate).formatted(.byteCount(style: .file)))/s")
        }
        parts.append("\(Int((event.fraction * 100).rounded()))%")
        return parts.joined(separator: " · ")
    }

    private static func generationDetail(_ event: GenerationProgressEvent) -> String {
        var parts: [String] = []
        switch event.phase {
        case .preparing: parts.append("Preparing")
        case .encodingText: parts.append("Reading the prompt")
        case .denoising(let step, let total): parts.append("Step \(step) of \(total)")
        case .decoding: parts.append("Developing the image")
        case .saving: parts.append("Saving")
        }
        if let pace = event.secondsPerStep {
            parts.append(String(format: "%.1f s/step", pace))
        }
        if let left = event.estimatedSecondsRemaining, left >= 1 {
            parts.append("~\(Int(left.rounded())) s left")
        }
        return parts.joined(separator: " · ")
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000_000).rounded())) GB"
    }
}
