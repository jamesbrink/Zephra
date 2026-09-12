import SwiftUI
import ZephraLinkClient
import ZephraLinkProtocol

/// The middle of the canvas: the run in flight while there is one, and otherwise the newest
/// picture the Mac has made.
///
/// The same order of precedence the Mac's `CanvasStateView` follows. A run showing its frames
/// beats a finished picture, because what the model is doing now is what somebody picked the
/// phone up to see; before the first frame lands the run's own rectangle stands in, which is
/// the honest thing to show.
///
/// A frame already here stays through a drop — the run is very likely still being made — but
/// the rectangle that stands in before the first one says "Reconnecting" rather than repeating
/// the phase the Mac was in when the link went.
struct CanvasPicture: View {
    @Environment(LinkClient.self) private var client
    /// Where the phone is looking, so a tap on the picture puts the keyboard away.
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        picture
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A tap up here means "I am looking at the picture, not typing". Simultaneous
            // rather than an `onTapGesture`, which would swallow the taps a clip's own
            // controls are waiting for.
            .simultaneousGesture(TapGesture().onEnded { selection.promptIsFocused = false })
    }

    @ViewBuilder private var picture: some View {
        if isGenerating {
            if let frame = client.preview {
                LivePreviewView(frame: frame, aspect: runAspect)
            } else {
                RunPlaceholderView(
                    phase: client.snapshot?.engine.phase,
                    isLive: client.connection.isLive)
                    .aspectRatio(runAspect, contentMode: .fit)
            }
        } else if let entry = newest, let name = entry.fileName {
            if entry.isVideo {
                ClipPicture(name: name)
            } else {
                ItemPicture(name: name)
            }
        } else {
            ContentUnavailableView(
                "Nothing yet", systemImage: "photo.on.rectangle.angled",
                description: Text("What your Mac makes next appears here."))
        }
    }

    /// Whether the Mac is rendering something right now, the decode after the last step
    /// included: the frames stay on screen until the picture itself lands.
    private var isGenerating: Bool {
        guard let engine = client.snapshot?.engine else { return false }
        return engine.kind == .generating || engine.isFinishing
    }

    /// The shape of the run in flight, so the frames sit in the rectangle the finished picture
    /// will arrive in and nothing jumps. The run's own size first; the frame's own only when
    /// there is no run to ask.
    private var runAspect: Double {
        if let running = client.snapshot?.running, running.height > 0 {
            return Double(running.width) / Double(running.height)
        }
        if let frame = client.preview, frame.height > 0 {
            return Double(frame.width) / Double(frame.height)
        }
        return 1
    }

    /// The newest finished picture this session, which is what the Mac's history holds first.
    private var newest: HistoryEntry? {
        client.snapshot?.history.first { $0.fileName != nil }
    }
}
