import Foundation
import ZephraCore
import ZephraEngine

/// The second line under the canvas headline: file counts while downloading, the component
/// while building, the pace while generating, the tile while upscaling. The headline itself
/// and the subtitle are `EngineState+Display`.
extension EngineState {
    /// The second line under the headline, or nil when the state has nothing to measure.
    var detail: String? { detail(clip: false) }

    /// The second line, worded for a clip when the run in flight makes one: its latents are
    /// developed into frames and the frames encoded, where a picture is developed and saved.
    func detail(clip: Bool) -> String? {
        switch self {
        case .downloading(let event):
            Self.downloadDetail(event)
        case .building(let event):
            Self.buildDetail(event)
        case .generating(let event):
            Self.generationDetail(event, clip: clip)
        case .upscaling(let event):
            "Tile \(event.completedTiles) of \(event.totalTiles)"
        default:
            nil
        }
    }

    /// What the running generation is doing right now, in a few words and without the pace.
    var generationPhase: String? { generationPhase(clip: false) }

    /// The phase worded for the kind of run: what the empty canvas says while the first frame
    /// is on its way, and what the finishing note over the last frame says once the steps are
    /// done.
    func generationPhase(clip: Bool) -> String? {
        guard case .generating(let event) = self else { return nil }
        return Self.phaseText(event.phase, clip: clip)
    }

    private static func downloadDetail(_ event: DownloadProgressEvent) -> String {
        var parts = ["File \(event.completedFiles) of \(event.totalFiles)"]
        if let rate = event.bytesPerSecond, rate > 0 {
            parts.append("\(Int64(rate).formatted(.byteCount(style: .file)))/s")
        }
        parts.append("\(Int((event.fraction * 100).rounded()))%")
        return parts.joined(separator: " · ")
    }

    private static func buildDetail(_ event: BuildProgressEvent) -> String {
        let parts = [
            "Packing the \(event.component)",
            "\(event.completedComponents) of \(event.totalComponents)",
            "\(Int((event.fraction * 100).rounded()))%",
        ]
        return parts.joined(separator: " · ")
    }

    private static func phaseText(_ phase: GenerationPhase, clip: Bool) -> String {
        switch phase {
        case .preparing: "Preparing"
        case .encodingText: "Reading the prompt"
        case .denoising(let step, let total): "Step \(step) of \(total)"
        case .decoding: clip ? "Developing the clip" : "Developing the image"
        case .saving: clip ? "Encoding the clip" : "Saving"
        }
    }

    /// The phase, with the pace and the countdown while the loop is what is running: a decode
    /// has no pace, and "Developing the clip · 7.0 s/step" would read as though it had.
    private static func generationDetail(_ event: GenerationProgressEvent, clip: Bool) -> String {
        var parts = [phaseText(event.phase, clip: clip)]
        guard case .denoising = event.phase else { return parts[0] }
        if let pace = event.secondsPerStep {
            parts.append(String(format: "%.1f s/step", pace))
        }
        if let left = event.estimatedSecondsRemaining, left >= 1 {
            parts.append("~\(DurationLabel.text(seconds: left)) left")
        }
        return parts.joined(separator: " · ")
    }
}
