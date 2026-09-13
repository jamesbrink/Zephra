import SwiftUI

struct LibraryOpeningCell: View {
    let entry: CachedEntry
    @Environment(\.openLibraryItem) private var open
    var body: some View {
        LibraryCell(entry: entry).onTapGesture { open(entry) }
    }
}
