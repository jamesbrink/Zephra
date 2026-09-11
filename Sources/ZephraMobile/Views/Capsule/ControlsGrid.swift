import SwiftUI
import ZephraLinkProtocol

/// The settings under the prompt, each under a small label: size, steps, length, guidance,
/// strength, seed.
///
/// The Mac's `ControlsRow`, wrapped into the width of a phone. The rules for what is drawn are
/// the Mac's own and read from the same capabilities: guidance only where the model responds
/// to it, steps only where the count is a choice, length only for a model that makes clips,
/// and strength only while a picture is in the well on a model that starts from a noised copy
/// of it.
struct ControlsGrid: View {
    /// What the model in force will accept.
    let capabilities: CapabilitiesSummary
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        let model = capabilities.capabilities
        VStack(alignment: .leading, spacing: 12) {
            ControlLabel("Size") { SizeMenu(capabilities: capabilities) }
            if model.adjustsSteps {
                ControlLabel("Steps") { StepsControl(capabilities: capabilities) }
            }
            if model.adjustsFrames {
                ControlLabel("Length") { DurationControl(capabilities: capabilities) }
            }
            if model.adjustsGuidance {
                ControlLabel("Guidance") { GuidanceControl(capabilities: capabilities) }
            }
            if draft.reference != nil && model.adjustsReferenceStrength {
                ControlLabel("Strength") { ReferenceStrengthControl(capabilities: capabilities) }
            }
            ControlLabel("Seed") { SeedControl() }
        }
    }
}
