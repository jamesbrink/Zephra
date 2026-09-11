import SwiftUI
import ZephraLinkClient
import ZephraStyle

/// What the Mac is making, and the capsule that asks it for more.
///
/// The Mac's canvas, in a phone's proportions: the picture fills the screen, the model is
/// named in the toolbar, and the capsule is a safe-area inset along the bottom edge rather
/// than a sheet — a sheet covers the tab bar, and the four surfaces have to stay one tap
/// apart while a prompt is being typed.
struct CanvasScreen: View {
    @Environment(LinkClient.self) private var client
    @Environment(PromptDraft.self) private var draft
    /// Whether the capsule is showing its settings. A frozen launch can open with it up, which
    /// is the only way to photograph the controls.
    @State private var capsuleExpanded = MobilePreview.capsuleIsExpanded

    var body: some View {
        NavigationStack {
            CanvasPicture()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, MobileChrome.sideMargin)
                .background(Color.canvasBackground)
                .navigationTitle(client.snapshot?.hostName ?? "Zephra")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { ModelMenu() } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PromptCapsule(isExpanded: $capsuleExpanded)
                }
                // The first snapshot is the Mac saying which model is in force and what it
                // defaults to; `adopt` takes only that first one, so nothing here can land on
                // a prompt somebody is in the middle of typing.
                .onChange(of: client.snapshot?.model.id, initial: true) { _, _ in
                    draft.adopt(client.snapshot)
                }
        }
    }
}
