import SwiftUI
import ZephraCore
import ZephraEngine

/// How long the clip should run, on a model that makes clips: a menu of whole seconds, each
/// standing for the frame count on the model's own ladder nearest to it.
///
/// Seconds rather than frames, because a person asks for a two-second clip and not a
/// forty-nine-frame one; the frame count is what `GenerationSettings.frames` holds, and the
/// label shows both so the record's number is not a surprise.
struct DurationControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        let capabilities = store.descriptor.capabilities
        Menu {
            ForEach(Self.choices(capabilities), id: \.self) { frames in
                Button {
                    store.settings.frames = frames
                } label: {
                    let title = Self.label(frames: frames, rate: capabilities.frameRate)
                    if frames == store.settings.frames {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text(Self.label(frames: store.settings.frames, rate: capabilities.frameRate))
                .font(.callout).monospacedDigit() + MenuChevron.text
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .fixedSize()
        .help("Clip length")
        .accessibilityLabel("Clip length")
    }

    /// The frame counts offered: the shortest clip the model makes, then one per whole second
    /// the bounds allow, each the legal count nearest to that many seconds — at 24 fps on a
    /// ladder of eight, 25, 49, 73, 97 and 121 frames for one to five seconds.
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
        "\(DurationLabel.text(seconds: Double(frames) / rate, fraction: true)) · \(frames) frames"
    }
}

#Preview("Length") {
    DurationControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready, descriptor: ModelCatalog.ltx2Distilled4bit))
}
