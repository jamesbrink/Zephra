import SwiftUI
import ZephraLinkClient

/// Adopting external work is an explicit user action; watching never replaces the draft.
struct AdoptHostSettings: View {
    @Environment(HostConnections.self) private var hosts
    @Environment(PromptDraft.self) private var draft
    var body: some View {
        if let host = hosts.visible, let run = host.client.snapshot?.running {
            Button("Adopt \(host.name)'s Run Settings") {
                draft.followedPrompt = draft.settings.prompt
                draft.follow(run)
            }
        }
    }
}
