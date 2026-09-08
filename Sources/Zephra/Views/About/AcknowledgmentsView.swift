import SwiftUI

/// The Acknowledgments window: the third-party notices bundled with the app, whole, laid out
/// by `NoticesView`. This is the disclosure, so nothing is left out or summarised; the window
/// is where the About window's Acknowledgments button and Settings > About both lead.
struct AcknowledgmentsView: View {
    @State private var notices = NoticesDocument(blocks: [])

    var body: some View {
        ScrollView {
            NoticesView(document: notices)
                .padding(20)
        }
        .frame(minWidth: 440, minHeight: 320)
        .task {
            // Off the main actor: a few hundred lines, but nothing the window has to wait for.
            notices = await Task.detached { NoticesDocument.bundled() }.value
        }
    }
}

#Preview("Acknowledgments") {
    AcknowledgmentsView()
        .frame(width: 560, height: 640)
}
