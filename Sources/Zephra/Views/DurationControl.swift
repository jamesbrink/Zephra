import SwiftUI
import ZephraCore
import ZephraEngine

/// How long the clip should run, on a model that makes clips: a menu of whole seconds, each
/// standing for the frame count on the model's own ladder nearest to it.
///
/// `ClipLength` is the rule, in `ZephraCore`, because the phone's capsule draws the same menu;
/// this is the Mac's chrome over it and nothing else.
struct DurationControl: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        let capabilities = store.descriptor.capabilities
        Menu {
            ForEach(ClipLength.choices(capabilities), id: \.self) { frames in
                Button {
                    store.settings.frames = frames
                } label: {
                    let title = ClipLength.label(frames: frames, capabilities: capabilities)
                    if frames == store.settings.frames {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text(ClipLength.label(frames: store.settings.frames, capabilities: capabilities))
                .font(.callout).monospacedDigit() + MenuChevron.text
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .fixedSize()
        .help("Clip length")
        .accessibilityLabel("Clip length")
    }
}

#Preview("Length") {
    DurationControl()
        .padding()
        .environment(GenerationStore.preview(state: .ready, descriptor: ModelCatalog.ltx2Distilled4bit))
}
