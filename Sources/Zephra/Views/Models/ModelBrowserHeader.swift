import SwiftUI

/// The browser's headline and the one line under it.
///
/// No app icon and no "Choose your first model": that mark and that sentence belong to the
/// first launch, which is a different moment. This is a dialog somebody opened to look at what
/// else there is.
struct ModelBrowserHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models")
                .font(.headline)
            Text("Every model runs on this Mac. Download what you want, and load one when you "
                + "need it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

#Preview("Header") {
    ModelBrowserHeader()
        .frame(width: 760)
}
