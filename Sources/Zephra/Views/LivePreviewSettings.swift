import SwiftUI
import ZephraCore

/// How often a run stops to show the picture it is making: never, every so often, or after
/// every step.
///
/// Balanced is what every run did before there was a choice — a frame held back until frames
/// cost about a tenth of the run. Every step is for watching a picture form, and the caption
/// says what it costs, since on Qwen-Image 2.1 each frame is the picture's own decode.
struct LivePreviewSettings: View {
    @AppStorage(AppSettings.livePreview) private var cadence = AppSettings.initialLivePreview

    var body: some View {
        Section("Live preview") {
            Picker("Show the picture forming", selection: $cadence) {
                ForEach(PreviewCadence.allCases, id: \.self) { cadence in
                    Text(cadence.title).tag(cadence)
                }
            }
            .pickerStyle(.segmented)
            Text(Self.caption(for: cadence))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The line under the picker, about the choice in force. Applies to the next run.
    static func caption(for cadence: PreviewCadence) -> String {
        switch cadence {
        case .off:
            "No frames while the model works; the picture appears when it is done."
        case .balanced:
            "A frame every so often, held back so frames never cost more than about a tenth "
                + "of a run."
        case .everyStep:
            "Decodes a picture after every step, which slows each run; on Qwen-Image 2.1 "
                + "about a second a step."
        }
    }
}

#Preview("Live preview") {
    Form { LivePreviewSettings() }
        .formStyle(.grouped)
        .frame(width: 520, height: 160)
}
