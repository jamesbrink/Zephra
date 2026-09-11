import SwiftUI
import ZephraLinkProtocol

/// How many seeds one press of Generate is worth, which is the Mac's batch count.
///
/// The bounds are `GenerationRequest.countBounds`, the Mac's own limit, read from the protocol
/// rather than written down again: a request that asked for more would be clamped at the far
/// end anyway, and a control that offered it would be lying.
struct CountControl: View {
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        @Bindable var draft = draft
        Stepper(value: $draft.count, in: GenerationRequest.countBounds) {
            Text("\(draft.count) \(draft.count == 1 ? "seed" : "seeds")")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityLabel("Seeds per press")
        .accessibilityValue("\(draft.count)")
    }
}
