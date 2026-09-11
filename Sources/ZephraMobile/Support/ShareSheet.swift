import SwiftUI
import UIKit

/// The system's share sheet over one file.
///
/// `ShareLink` wherever there is a view to hang it on — the viewer's bar has one — and this
/// wherever there is not. A context menu's item cannot *be* a `ShareLink` and also do the
/// fetch that gets the file onto the phone first, so the menu asks for a share and this is
/// what the surface raises once the bytes are here. The Mac draws the same line between
/// `ShareLink` and `SharePicker`, for the same reason.
struct ShareSheet: UIViewControllerRepresentable {
    /// The file to offer.
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
