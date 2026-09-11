import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// How long the clip should run, on a model that makes clips: a menu of whole seconds, each
/// standing for the frame count on the model's own ladder nearest to it.
///
/// Seconds rather than frames, because a person asks for a two-second clip and not a
/// forty-nine-frame one; the label shows both, so the number the Mac records is not a surprise.
///
/// One pass's lengths only. The Mac offers longer clips as a chain of passes it plans itself
/// (`ChainPlan`), which lives in the engine the phone does not link; asking for a chain from
/// here is in `ROADMAP.md`.
struct DurationControl: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        let model = capabilities.capabilities
        Menu {
            ForEach(Self.choices(model), id: \.self) { frames in
                Button {
                    draft.settings.frames = frames
                } label: {
                    let title = Self.label(frames: frames, rate: model.frameRate)
                    if frames == draft.settings.frames {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text(Self.label(frames: draft.settings.frames, rate: model.frameRate))
                .font(.callout)
                .monospacedDigit()
        }
        .accessibilityLabel("Clip length")
    }

    /// The frame counts offered: the shortest clip the model makes, then one per whole second
    /// up to the longest single pass, each snapped to the `1 + k * frameAlignment` ladder.
    static func choices(_ capabilities: ModelCapabilities) -> [Int] {
        let bounds = capabilities.frameBounds
        let alignment = Double(capabilities.frameAlignment)
        var frames: Set<Int> = [bounds.lowerBound]
        var seconds = 1
        while Double(seconds) * capabilities.frameRate <= Double(bounds.upperBound) + alignment / 2 {
            let rungs = ((Double(seconds) * capabilities.frameRate - 1) / alignment).rounded()
            let count = 1 + Int(rungs) * capabilities.frameAlignment
            if bounds.contains(count) { frames.insert(count) }
            seconds += 1
        }
        return frames.sorted()
    }

    /// "2 s · 49 frames", with the seconds to one decimal only when they are not whole.
    static func label(frames: Int, rate: Double) -> String {
        let seconds = DurationLabel.text(seconds: Double(frames) / rate, fraction: true)
        return "\(seconds) · \(frames) frames"
    }
}
