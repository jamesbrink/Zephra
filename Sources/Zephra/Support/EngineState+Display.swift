import Foundation
import ZephraCore
import ZephraEngine

/// The words the canvas, the window subtitle and the File menu use for each engine state.
///
/// Copy rules: sentence case, active verbs, the same verb through the flow, and every
/// failure names a cause and a remedy. Nothing here apologises. The second line under a
/// headline — counts, rates, pace — is `EngineState+Detail`.
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

    /// The window subtitle, naming the model while it is being fetched. Which model is on its
    /// way is worth knowing there and nowhere else: every other state is about the one loaded.
    func subtitle(for descriptor: ModelDescriptor) -> String {
        guard case .downloading = self else { return subtitle }
        guard let detail else { return "Downloading \(descriptor.fullName)" }
        return "Downloading \(descriptor.fullName) · \(detail.prefix(1).lowercased() + detail.dropFirst())"
    }

    /// The state in a word or two.
    var statusLabel: String {
        switch self {
        case .idle: "Not loaded"
        case .checkingModel: "Checking model"
        case .downloading: "Downloading"
        case .building: "Building"
        case .loading: "Preparing"
        case .warmingUp: "Warming up"
        case .ready: "Ready"
        case .generating: "Generating"
        case .upscaling: "Upscaling"
        case .cancelling: "Stopping"
        case .failed: "Failed"
        }
    }

    /// What the File menu's ⌘. item says it will stop, so the menu names the thing rather
    /// than offering a bare "Cancel" over a download, a build and a generation alike. Title
    /// Case, because it is a menu item. A state with nothing to stop still says "Stop
    /// Generating", which is the item's resting name while it is greyed out.
    var stopCommandTitle: String {
        switch self {
        case .downloading: "Cancel Download"
        case .building: "Stop Building"
        case .checkingModel, .loading, .warmingUp: "Stop Loading"
        case .upscaling: "Stop Upscaling"
        case .idle, .ready, .generating, .cancelling, .failed: "Stop Generating"
        }
    }

    /// The headline the canvas shows, or nil when the canvas needs no headline.
    ///
    /// The model is named by `fullName`, the way the toolbar and the subtitle name it: the
    /// variant is what is being fetched or built, and "Z-Image Turbo" over a window whose
    /// toolbar says "Z-Image Turbo · 8-bit" reads as a different model. `availability` is what
    /// the disk said before the download began, and is where the size comes from when the
    /// transfer has not listed itself yet.
    func title(for descriptor: ModelDescriptor, availability: ModelAvailability?) -> String? {
        switch self {
        case .idle:
            "\(descriptor.fullName) isn't loaded yet."
        case .checkingModel, .loading:
            "Preparing model…"
        case .downloading(let event):
            "\(descriptor.fullName) needs a one-time "
                + "\(ByteCount.gigabytes(Self.transferBytes(event, availability, descriptor))) download."
        case .building:
            "Building \(descriptor.fullName). This happens once."
        case .warmingUp:
            "Warming up…"
        case .upscaling:
            "Upscaling…"
        case .cancelling:
            "Stopping after this step…"
        case .failed(let error):
            error.message
        case .ready, .generating:
            nil
        }
    }

    /// The bytes the download headline states: what is actually being fetched, not the
    /// catalog's figure for a Mac with nothing.
    ///
    /// The event's own total first, because it is the sum of the files the transfer listed
    /// after the descriptor's globs and after what was already on disk was counted — a cached
    /// Qwen-Image release with its adapter missing lists 1.7 GB, not 59.4. Before the listing
    /// lands, what availability said the disk was missing, which every backend fills from
    /// `ModelLocations.bytesToFetch` by the same rule. Only then the catalog's `transferBytes`,
    /// which is the release plus its adapters, since a Mac with nothing fetches both.
    private static func transferBytes(
        _ event: DownloadProgressEvent, _ availability: ModelAvailability?, _ descriptor: ModelDescriptor
    ) -> Int64 {
        if let total = event.totalBytes, total > 0 { return total }
        switch availability {
        case .needsDownload(let bytes), .needsDownloadAndBuild(let bytes): return bytes
        case .available, .needsBuild, .missing, nil: return descriptor.transferBytes
        }
    }

    /// How far along a download or a build is, for the bar under the headline, or nil when the
    /// state has no bar.
    var progressFraction: Double? {
        switch self {
        case .downloading(let event): event.fraction
        case .building(let event): event.fraction
        case .upscaling(let event): event.fraction
        default: nil
        }
    }

    /// The step the diffusion loop is on, and how many there are, while one is running.
    var denoisingProgress: (step: Int, total: Int)? {
        guard case .generating(let event) = self,
              case .denoising(let step, let total) = event.phase
        else { return nil }
        return (step, total)
    }
}
