import SwiftUI

struct PromptHistoryControls: View {
    @Environment(PromptDraft.self) private var draft
    @Environment(GenerationDispatch.self) private var dispatch
    @State private var history = MobilePromptHistory()
    var body: some View {
        HStack {
            Button("History", systemImage: "clock.arrow.circlepath") {
                history.showing = true
                Task { await history.refresh(dispatch) }
            }
            Spacer()
            Button("Previous Prompt", systemImage: "chevron.up") { step(true) }.labelStyle(.iconOnly)
                .disabled(history.entries.isEmpty)
            Button("Next Prompt", systemImage: "chevron.down") { step(false) }.labelStyle(.iconOnly)
                .disabled(history.entries.isEmpty)
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .sheet(isPresented: $history.showing) {
            PromptHistorySheet(history: history) { prompt in draft.settings.prompt = prompt; history.recall.reset() }
        }
        .task(id: dispatch.destination) { history.reset(); await history.refresh(dispatch) }
        .onChange(of: dispatch.hosts.hosts.map { $0.client.snapshot?.queue.map(\.id) ?? [] }) {
            Task { await history.refresh(dispatch) }
        }
        .onChange(of: dispatch.hosts.hosts.filter { $0.client.connection.isLive }.map(\.id)) {
            history.reset(); Task { await history.refresh(dispatch) }
        }
    }
    private func step(_ older: Bool) {
        if let prompt = history.recall.step(older: older, current: draft.settings.prompt, prompts: history.entries.map(\.prompt)) {
            draft.settings.prompt = prompt
        }
    }
}
