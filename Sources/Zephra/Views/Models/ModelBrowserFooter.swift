import SwiftUI
import ZephraCore
import ZephraEngine

/// What the selected card is for, and the one press that acts on it.
///
/// One button rather than a row of them: which of Download, Build, Use, Load and Done applies
/// is decided entirely by the disk and this Mac's memory, so `ModelBrowserAction` answers it
/// once and is tested without a sheet. A model whose transfer is already moving shows that
/// transfer's own row instead, with its Pause and Cancel Download — the person is looking at
/// the dialog where they just pressed Download, and sending them to Settings to stop it is a
/// worse answer than drawing the row they are already looking at.
struct ModelBrowserFooter: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The selected model, judged against this Mac.
    let choice: ModelChoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let download = liveDownload {
                ModelDownloadRow(download: download)
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
            if liveDownload == nil {
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
        .padding(.vertical, 12)
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
        case .done, .unavailable: break
        }
        if action.dismisses { dismiss() }
    }
}

#Preview("Footer") {
    ModelBrowserFooter(choice: ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30))[0])
        .frame(width: 760)
        .environment(GenerationStore.preview(state: .idle))
}
