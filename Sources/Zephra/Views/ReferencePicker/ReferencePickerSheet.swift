import SwiftUI
import ZephraEngine

/// A sheet offering library pictures as references, with a visible local-file alternative.
///
/// `onUse` is handed the chosen `LibraryItem`; turning it into reference bytes is
/// `ReferenceAdoption`'s job; this sheet knows nothing about PNG chunks or which actor that
/// runs on, only which picture was picked.
struct ReferencePickerSheet: View {
    /// What to do with the image chosen, once the sheet has closed.
    let onUse: (LibraryItem) -> Void

    @State private var selection = ReferencePickerSelection()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose from Library")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            Divider()
            ReferencePickerSearch(selection: selection)
                .padding(12)
            ReferencePickerGrid(selection: selection, confirm: use)
            Divider()
            footer
        }
        .frame(width: 640, height: 520)
        .onExitCommand { dismiss() }
    }

    private var footer: some View {
        HStack {
            ReferenceFileButton()
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Use") { confirmSelection() }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.item == nil)
        }
        .padding(16)
    }

    private func confirmSelection() {
        guard let item = selection.item else { return }
        use(item)
    }

    /// What both the "Use" button and a double-click on a cell do: hand the picture to the
    /// caller and close, so the two ways of confirming a choice cannot disagree about what
    /// happens next.
    private func use(_ item: LibraryItem) {
        onUse(item)
        dismiss()
    }
}

#Preview("Picker") {
    Color.clear
        .frame(width: 700, height: 600)
        .sheet(isPresented: .constant(true)) {
            ReferencePickerSheet { _ in }
                .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
                .environment(PreviewImages.library(count: 24))
                .environment(ThumbnailCache())
        }
}
