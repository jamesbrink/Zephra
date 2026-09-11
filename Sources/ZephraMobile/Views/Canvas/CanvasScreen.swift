import SwiftUI
import ZephraLinkProtocol

/// What the Mac is making. A placeholder for now: the live preview, the prompt sheet and the
/// step bar come next, and each replaces this from the inside.
struct CanvasScreen: View {
    @Environment(MobileSession.self) private var session

    var body: some View {
        SurfacePlaceholder(
            title: MobileTab.canvas.title, symbol: MobileTab.canvas.symbol, fact: fact)
    }

    /// Where the Mac's engine is, with the step it is on where there is one.
    ///
    /// `phase` is preferred wherever the Mac sent one — "Denoising", "Decoding", "Saving" are
    /// the Mac's own words, and taking them means the two ends can never disagree about what
    /// is happening. Only the cases that carry no phase get a sentence of their own.
    private var fact: String? {
        guard let engine = session.snapshot?.engine else { return nil }
        let headline = engine.phase ?? Self.headline(engine.kind)
        guard let step = engine.step, let steps = engine.steps else { return headline }
        return "\(headline), step \(step) of \(steps)"
    }

    /// One line for a state the Mac sent no phase for.
    private static func headline(_ kind: EngineStateDTO.Kind) -> String {
        switch kind {
        case .idle: "Idle"
        case .checkingModel: "Checking the model"
        case .downloading: "Downloading"
        case .building: "Building"
        case .loading: "Loading"
        case .warmingUp: "Warming up"
        case .ready: "Ready"
        case .generating: "Generating"
        case .upscaling: "Upscaling"
        case .cancelling: "Stopping"
        case .failed: "Something went wrong"
        }
    }
}
