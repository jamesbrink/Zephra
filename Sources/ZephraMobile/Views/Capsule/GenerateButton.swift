import SwiftUI
import ZephraLinkProtocol

struct GenerateButton: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 10) {
                if dispatch.hosts.client.snapshot?.running != nil { StopRunButton() }
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(dispatch.isSending || !draft.settings.isReadyToGenerate || dispatch.target == nil)
            }
            if let note = dispatch.note {
                Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
    }
    private func generate() {
        if MobileSettings.flag(MobileSettings.randomizeSeedEachRun) { draft.randomizeSeed() }
        let request = GenerationRequest(modelID: draft.modelID, count: draft.count, settings: draft.settings)
        let reference = draft.reference
        let generation = StrictGeneration(request: request, input: reference.map { GenerationInput(data: $0, originHost: draft.settings.referenceOrigin.flatMap { dispatch.hosts.catalog.entry(named: $0)?.hostID }, dimensions: draft.referenceSize) })
        Task { await dispatch.send(generation, reference: reference) }
    }
}
