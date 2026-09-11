import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// How much of the picture in the well survives.
///
/// Shown only while there is a picture and only where `referenceStrengthBounds` is a real
/// range: a model that conditions on the picture directly declares the degenerate `1...1` and
/// has nothing to offer here, the same way a distilled model hides guidance. "Lower keeps more
/// of the picture" is true of every role this draws for; `ReferenceRole` says the rest, and
/// says it in the Mac's own words.
struct ReferenceStrengthControl: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        let model = capabilities.capabilities
        if model.adjustsReferenceStrength {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Slider(value: value, in: model.referenceStrengthBounds, step: 0.05)
                    Text(
                        draft.settings.referenceStrength,
                        format: .number.precision(.fractionLength(2))
                    )
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .trailing)
                }
                Text(ReferenceRole(capabilities: model).strengthHelp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("Reference strength")
        }
    }

    /// The strength, held inside the model's bounds whatever it arrived as.
    private var value: Binding<Double> {
        let bounds = capabilities.referenceStrengthBounds
        return Binding(
            get: {
                min(max(draft.settings.referenceStrength, bounds.lowerBound), bounds.upperBound)
            },
            set: { draft.settings.referenceStrength = $0 })
    }
}
