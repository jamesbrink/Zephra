import SwiftUI

/// What the phone is holding of the Mac's library, and how to be rid of it.
///
/// A placeholder, and its own file so that the agent who builds the library's cache replaces
/// this one file rather than editing a settings screen around it. What goes here is the size
/// on disk and a button that empties it; there is nothing to empty yet, because nothing is
/// kept yet.
struct CacheRow: View {
    var body: some View {
        LabeledContent("Cache", value: "Coming with the library")
    }
}

#Preview("Cache") {
    Form { CacheRow() }
}
