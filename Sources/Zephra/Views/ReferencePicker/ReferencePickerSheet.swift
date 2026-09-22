import SwiftUI
import ZephraEngine

/// A sheet offering library pictures as references, with a visible local-file alternative.
///
/// `onUse` is handed the pictures chosen, in the grid's own order, which is the order the model
/// reads them in; turning them into reference bytes is `ReferenceAdoption`'s job. This sheet
/// knows nothing about PNG chunks or which actor that runs on, only which pictures were picked.
///
/// `limit` is how many the model reads. It is taken in `init` and put straight into the
/// selection rather than stored, so the sheet keeps to three stored properties.
struct ReferencePickerSheet: View {
    /// What to do with the images chosen, once the sheet has closed.
    let onUse: ([LibraryItem]) -> Void

    @State private var selection: ReferencePickerSelection
    @Environment(\.dismiss) private var dismiss

    /// Creates the sheet for a model that reads `limit` pictures.
    init(limit: Int = 1, onUse: @escaping ([LibraryItem]) -> Void) {
        self.onUse = onUse
        _selection = State(initialValue: ReferencePickerSelection(limit: limit))
    }

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
            Button(selection.useTitle) { confirmSelection() }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.ids.isEmpty)
        }
        .padding(16)
    }

    private func confirmSelection() {
        // `picked` is the grid's own order, which is the order the tiles will sit in; a set of
        // ids has none, and the footer has no index to put one back.
        guard !selection.picked.isEmpty else { return }
        use(selection.picked)
    }

    /// What both the "Use" button and a double-click on a cell do: hand the pictures to the
    /// caller and close, so the two ways of confirming a choice cannot disagree about what
    /// happens next.
    private func use(_ items: [LibraryItem]) {
        onUse(items)
        dismiss()
    }
}

#Preview("Picker") {
    Color.clear
        .frame(width: 700, height: 600)
        .sheet(isPresented: .constant(true)) {
            ReferencePickerSheet(limit: 10) { _ in }
                .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
                .environment(PreviewImages.library(count: 24))
                .environment(ThumbnailCache())
        }
}
