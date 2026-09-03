import SwiftUI

/// One sentence about something that did not work, floating over whatever it is about.
///
/// A notice, not an error: by the time one of these is drawn the app has already put itself
/// back to a state that is true, so there is nothing to decide and nothing to dismiss. It says
/// what the file system said and goes away when the next thing works.
///
/// One view for all of them so a saved image, an opened one and a favourite that would not
/// write look like the same kind of event, which they are.
struct NoticeCapsule: View {
    /// What went wrong, already phrased for the person reading it.
    let message: String

    /// A notice saying `message`.
    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(message)
    }
}

#Preview("Notice") {
    NoticeCapsule("Couldn't save that change to the image. The volume is read-only.")
        .padding(30)
        .frame(width: 480)
        .background(Color.canvasBackground)
}
