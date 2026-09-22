import SwiftUI
import ZephraStyle

/// The Mac's library door: a picture already on the Mac, chosen without it ever coming down to
/// the phone until it is picked.
///
/// Two shapes, one door. Under the well it is a small bordered button beside the camera roll's;
/// at the end of a strip it is the tile that says there is room for another picture, which is
/// where somebody already looking at the row will reach for it.
struct ReferenceLibraryButton: View {
    /// Whether it is drawn as the strip's last tile rather than as a button under the well.
    var asTile = false
    /// How many more pictures the well would take, which the picker reads to allow several.
    var room = 1
    /// Whether the picker is up.
    @State private var isPicking = false

    var body: some View {
        button
            .accessibilityLabel(asTile ? "Add a picture" : "From your Mac's library")
            .sheet(isPresented: $isPicking) { ReferencePickerSheet(room: room) }
    }

    @ViewBuilder private var button: some View {
        if asTile {
            Button { isPicking = true } label: { tile }.buttonStyle(.plain)
        } else {
            Button { isPicking = true } label: { Image(systemName: "square.grid.2x2") }
                .buttonStyle(.bordered)
        }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.wellRadius, style: .continuous)
            .fill(ZephraChrome.wellFill)
            .frame(width: 72, height: 72)
            .overlay {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}
