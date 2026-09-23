import SwiftUI

/// The picker's one press: the pictures marked in the grid become the next run's references.
///
/// A view of its own rather than a closure in the sheet's toolbar, for `DismissSheetButton`'s
/// own reason: a sheet with a room, a catalog, a selection *and* a way to close is a view past
/// the three stored properties the rules allow, and the way to close is the one of the four
/// that is the same everywhere.
struct ReferencePickerConfirm: View {
    /// The names marked in the grid, in the order they were marked, which is the order the
    /// model will read them in.
    @Binding var selection: [String]

    @Environment(ReferenceIntent.self) private var reference
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(selection.count > 1 ? "Add \(selection.count)" : "Use") {
            reference.use(selection)
            dismiss()
        }
        .disabled(selection.isEmpty)
    }
}
