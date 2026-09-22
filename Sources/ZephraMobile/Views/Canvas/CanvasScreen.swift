import SwiftUI
import ZephraLinkClient
import ZephraStyle
import ZephraCore

/// What the Mac is making, and the capsule that asks it for more.
///
/// The Mac's canvas, in a phone's proportions: the picture fills the screen, the model is
/// named in the toolbar, and the capsule is a safe-area inset along the bottom edge rather
/// than a sheet — a sheet covers the tab bar, and the four surfaces have to stay one tap
/// apart while a prompt is being typed.
struct CanvasScreen: View {
    @Environment(LinkClient.self) private var client
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        NavigationStack {
            CanvasLayout()
                .background(Color.canvasBackground)
                .navigationTitle(client.snapshot?.hostName ?? "Zephra")
                .navigationBarTitleDisplayMode(.inline)
                .modifier(CanvasModelToolbar())
                // The first snapshot seeds the capsule, and a run the Mac starts fills it in
                // the way the Mac's own capsule follows the run; never over a prompt somebody
                // is in the middle of typing.
                .modifier(DraftFollowsMac())
                // "Use as Reference", said over in the library and heard here.
                .modifier(ReferenceIntentReader(fill: fill))
        }
    }

    /// Puts the pictures in the well, fitted to whatever model the next press names, by D7's
    /// one rule: they are added where there is room and replace the strip where there is not.
    private func fill(_ pictures: [ReferencePicture]) -> Bool {
        guard let model = dispatch.models.first(where: { $0.id == draft.modelID }) else { return false }
        return draft.useAsReferences(pictures, fitting: model.capabilities.capabilities)
    }
}
