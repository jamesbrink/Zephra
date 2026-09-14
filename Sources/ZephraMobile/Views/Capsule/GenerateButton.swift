import SwiftUI
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
            if let note = referenceIntent.note ?? (dispatch.note == dispatch.reason ? nil : dispatch.note) {
                Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if referenceIntent.note != nil && !referenceIntent.isResolving {
                Button("Clear reference request") { referenceIntent.clear(); draft.clearReference() }.font(.caption)
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

    private func generate() {
        guard referenceIntent.canGenerate else { return }
        if MobileSettings.flag(MobileSettings.randomizeSeedEachRun) { draft.randomizeSeed() }
        let request = GenerationRequest(modelID: draft.modelID, count: draft.count, settings: draft.settings)
        let reference = draft.reference
        let generation = StrictGeneration(request: request, input: reference.map { GenerationInput(data: $0, originHost: draft.settings.referenceOrigin.flatMap { dispatch.hosts.catalog.entry(named: $0)?.hostID }, dimensions: draft.referenceSize) })
        Task { await dispatch.send(generation, reference: reference) }
    }
}
