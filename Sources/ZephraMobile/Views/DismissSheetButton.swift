import SwiftUI

/// A button that does one thing and closes the sheet it is in.
///
/// It exists so a sheet does not have to hold `@Environment(\.dismiss)` itself: a sheet with a
/// picture, a catalog, its own draft *and* a way to close is a view over the three stored
/// properties the rules allow, and the way to close is the one of the four that is the same
/// everywhere.
struct DismissSheetButton: View {
    /// The word on it.
    let title: String
    /// What to do before closing, or nil for a plain Cancel.
    var action: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(title) {
            action?()
            dismiss()
        }
    }
}
