import SwiftUI
import ZephraCore
import ZephraLinkProtocol

struct GenerateButton: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @Environment(ReferenceIntent.self) private var referenceIntent

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 12) { actions }
            }
            if let note = referenceIntent.note
                ?? draft.referenceNote
                ?? (dispatch.note == dispatch.reason ? nil : dispatch.note)
                ?? dispatch.runNote
                ?? dispatch.loadNote(for: draft.modelID) {
                Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if referenceIntent.note != nil && !referenceIntent.isResolving {
                Button("Clear reference request") { referenceIntent.clear(); draft.clearReferences() }.font(.caption)
            }
        }
    }
    @ViewBuilder private var actions: some View {
        if dispatch.hosts.client.snapshot?.running != nil { StopRunButton() }
        Button("Generate") { generate() }
            .buttonStyle(.borderedProminent)
            .fixedSize()
            .disabled(!referenceIntent.canGenerate || dispatch.isSending
                || !draft.settings.isReadyToGenerate || !dispatch.canSend)
    }

    /// One press: a fresh seed where the preference asks for one, the request clamped through
    /// the destination's own capabilities, and every picture the destination will read beside
    /// it. The clamp is what trims a strip to one picture for a Mac whose summary never
    /// mentioned a count, so the phone asks for what that Mac would have allowed rather than
    /// paying for pictures over a relay that the far end will refuse.
    ///
    /// A destination that has not named this model has no capabilities to clamp by, but the
    /// well's pictures still ride along: `PromptDraft.nextSubmission` is the one path either
    /// way, so the settings a Mac reads always carry the same pictures the blobs beside them do.
    private func generate() {
        guard referenceIntent.canGenerate else { return }
        let randomizes = MobileSettings.flag(MobileSettings.randomizeSeedEachRun)
        let summary = dispatch.models.first(where: { $0.id == draft.modelID })?.capabilities
        let (request, pictures) = draft.nextSubmission(
            summary: summary, randomizingSeed: randomizes)
        let generation = StrictGeneration(
            request: request, inputs: dispatch.inputs(for: pictures))
        Task { await dispatch.send(generation, references: pictures.map(\.data)) }
    }
}
