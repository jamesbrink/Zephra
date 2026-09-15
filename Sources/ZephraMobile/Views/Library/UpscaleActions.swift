import SwiftUI

/// Scaling happens on the picture's source Mac; clips never offer picture-only actions.
struct UpscaleActions: View {
    let entry: CachedEntry
    @Environment(LibraryCatalog.self) private var catalog
    @Environment(\.upscaleLibraryImage) private var upscale

    var body: some View {
        if !entry.isVideo {
            Button("Upscale 2×", systemImage: "arrow.up.left.and.arrow.down.right") {
                upscale(entry, 2)
            }
            .disabled(!catalog.isLive(for: entry))
            Button("Upscale 4×", systemImage: "arrow.up.left.and.arrow.down.right") {
                upscale(entry, 4)
            }
            .disabled(!catalog.isLive(for: entry))
        }
    }
}

extension EnvironmentValues {
    @Entry var upscaleLibraryImage: (CachedEntry, Int) -> Void = { _, _ in }
}
