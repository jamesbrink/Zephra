import SwiftUI

/// The Mac's library door: a picture already on the Mac, chosen without it ever coming down to
/// the phone until it is picked.
struct ReferenceLibraryButton: View {
    /// Whether the picker is up.
    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking = true
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("From your Mac's library")
        .sheet(isPresented: $isPicking) { ReferencePickerSheet() }
    }
}
