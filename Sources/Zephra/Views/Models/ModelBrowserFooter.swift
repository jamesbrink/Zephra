import SwiftUI
import ZephraCore
import ZephraEngine

/// What the selected card is for, and the one press that acts on it.
///
/// One button rather than a row of them: which of Download, Build, Use and Load applies is
/// decided entirely by the disk and this Mac's memory, so `ModelBrowserAction` answers it once
/// and is tested without a sheet. The model that is chosen and already in gets no button at
/// all — Done is standing there already, and a second Done beside it would be two ways out of
/// a dialog that has one.
///
/// A model whose transfer is already moving shows that transfer's own row instead, with its
/// Pause and Cancel Download: the person is looking at the dialog where they just pressed
/// Download, and sending them to Settings to stop it is a worse answer than drawing the row
/// they are already looking at.
struct ModelBrowserFooter: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The selected model, judged against this Mac.
    let choice: ModelChoice

    /// The footer's own height, fixed and the same in every state. The sheet is 560 tall and
    /// the grid scrolls inside what is left, so a footer that grew when Download was pressed
    /// would resize the grid under the card somebody had just chosen — the one card they were
    /// looking at.
    ///
    /// 112 is what `ModelDownloadRow` needs down to its buttons: the name, the status line, the
    /// bar, the byte counts and Pause / Cancel Download, with its two trailing caption
    /// paragraphs clipped. Clipped, never forked: two copies of Pause and Cancel Download would
    /// be two sets of disabled reasoning to keep in step.
    private static let height: CGFloat = 112

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if let download = liveDownload {
                ModelDownloadRow(download: download)
                    .frame(maxWidth: 420, maxHeight: Self.height, alignment: .topLeading)
                    .clipped()
            } else {
                Text(choice.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            if liveDownload == nil, action.isDrawn {
                Button(action.label) { press() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!action.isEnabled || !store.acceptsWork)
                    .help(choice.isSelectable
                        ? (store.availability[choice.id]?.reason ?? choice.reason)
                        : choice.reason)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
    }

    /// What the button says and does for this card.
    private var action: ModelBrowserAction {
        ModelBrowserAction.action(
            availability: store.availability[choice.id],
            fit: choice.fit,
            isChosen: choice.id == store.descriptor.id,
            isLoaded: store.loadedDescriptor?.id == choice.id)
    }

    /// The selected model's transfer while one is moving, which replaces the button with the
    /// row that owns it. Computed rather than stored: a view is allowed three properties and
    /// this one is the store's, not the footer's.
    private var liveDownload: ModelDownload? {
        store.downloads.items.first {
            $0.model.id == choice.id
                && ($0.status == .queued || $0.status == .downloading || $0.status == .paused)
        }
    }

    /// `downloadModel` rather than `resumeDownload`: a button that says "Download 5.4 GB" must
    /// fetch and stop, even for the model already chosen, which `resumeDownload` would load.
    private func press() {
        switch action {
        case .download, .build: store.downloadModel(choice.model)
        case .use: store.switchModelFromInterface(to: choice.model)
        case .load: store.loadModel()
        case .done, .pending, .unavailable: break
        }
        if action.dismisses { dismiss() }
    }
}

#Preview("Footer") {
    ModelBrowserFooter(choice: ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30))[0])
        .frame(width: 760)
        .environment(GenerationStore.preview(state: .idle))
}
