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
    /// Where the phone is looking, which is where the capsule's own open-or-shut lives: a
    /// frozen launch can open with it up, which is the only way to photograph the controls.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        @Bindable var selection = selection
        return NavigationStack {
            CanvasPicture()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, MobileChrome.sideMargin)
                .background(Color.canvasBackground)
                .navigationTitle(client.snapshot?.hostName ?? "Zephra")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { ModelMenu() } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PromptCapsule(isExpanded: $selection.capsuleIsExpanded)
                }
                // The first snapshot seeds the capsule, and a run the Mac starts fills it in
                // the way the Mac's own capsule follows the run; never over a prompt somebody
                // is in the middle of typing.
                .modifier(DraftFollowsMac())
                // "Use as Reference", said over in the library and heard here.
                .modifier(ReferenceIntentReader(fill: fill))
        }
    }

    /// Puts one picture in the well, fitted to whatever model the next press names.
    private func fill(_ data: Data, origin: String) async {
        guard let snapshot = client.snapshot else { return }
        await ReferenceAdoption.adopt(
            data, origin: origin, into: draft,
            fitting: snapshot.model(named: draft.modelID).capabilities)
    }
}
