import SwiftUI
import ZephraLinkClient

/// What the capsule takes from the Mac, and when.
///
/// Two moments, one modifier, so the canvas names the rule once rather than carrying two
/// `onChange`s with a comment each. The first snapshot is the Mac saying which model is in
/// force and what it defaults to; `adopt` takes only that first one. A run the Mac starts is
/// followed as it starts, and `PromptDraft.follow` is where the line is drawn: the run's
/// settings land only on a draft nobody has typed into, so nothing here can land on a prompt
/// somebody is in the middle of writing.
struct DraftFollowsMac: ViewModifier {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft

    func body(content: Content) -> some View {
        content
            .onChange(of: client.snapshot?.model.id, initial: true) { _, _ in
                draft.adopt(client.snapshot)
            }
            .onChange(of: client.snapshot?.running?.id, initial: true) { _, _ in
                draft.follow(client.snapshot?.running)
            }
    }
}
