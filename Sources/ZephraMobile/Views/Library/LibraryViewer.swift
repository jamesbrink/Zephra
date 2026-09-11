import SwiftUI
import ZephraStyle

/// One picture full size, with every other picture in the grid a swipe away.
///
/// Built the way Photos is: a horizontal pager of pages, each a scroll view that zooms, and a
/// pull downwards that closes it. The pager is a lazy `ScrollView` rather than a `TabView`, so
/// the whole grid can be handed over and only the pages beside the one on screen are built —
/// which is what lets a swipe carry on past the day the picture was filed under. A clip plays
/// in place through AVKit rather than showing its poster: the poster is how a clip is filed,
/// not how it is watched.
///
/// Every gesture, the pull included, is UIKit's, inside `ZoomingScrollView` or on the clip's
/// player; what it saw comes back up through `\.viewerGestures` and lands in one `ViewerPose`.
/// Which picture the pager has settled on goes back out through `\.viewerPaged`, so the
/// surface underneath can close the viewer into that picture's cell (`ViewerCover`).
struct LibraryViewer: View {
    /// The pictures, in the order the grid showed them.
    let entries: [CachedEntry]
    /// Which one is on screen, whether the chrome is, and how far it has been pulled.
    @State private var pose: ViewerPose

    @Environment(\.viewerPaged) private var paged

    /// Opens the pictures at one of them.
    init(entries: [CachedEntry], opening fileName: String) {
        self.entries = entries
        _pose = State(initialValue: ViewerPose(current: fileName))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: MobileChrome.viewerPageGap) {
                ForEach(entries) { entry in
                    ViewerPicture(entry: entry)
                        .containerRelativeFrame(.horizontal)
                        .environment(\.viewerPageIsCurrent, entry.fileName == pose.current)
                        .id(entry.fileName)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $pose.current)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        // The pull is inside the environment, not outside it: `ViewerPull` adds its own
        // closure to what is set here, and an environment set inside it would replace that.
        .modifier(ViewerPull(pull: $pose.pull, isEnabled: !pose.isZoomed))
        .environment(\.viewerGestures, gestures)
        .overlay(alignment: .top) { chrome { LibraryViewerTitle(entry: shown) } }
        .overlay(alignment: .bottom) {
            if let shown { chrome { LibraryViewerBar(entry: shown) } }
        }
        .modifier(LibraryRequests())
        .statusBarHidden()
        .presentationBackground(.clear)
        .onChange(of: pose.current) { _, current in
            if let current { paged(current) }
        }
    }

    /// The picture on screen, or nil once the last one has been deleted.
    private var shown: CachedEntry? {
        entries.first { $0.fileName == pose.current } ?? entries.first
    }

    /// A strip of controls that a tap on the picture puts away and another brings back.
    private func chrome<Strip: View>(@ViewBuilder _ strip: () -> Strip) -> some View {
        strip()
            .opacity(pose.chromeIsHidden ? 0 : 1)
            .allowsHitTesting(!pose.chromeIsHidden)
    }

    /// What a page's fingers do to the pose.
    private var gestures: ViewerGestures {
        ViewerGestures(
            tapped: { withAnimation(fade) { pose.chromeIsHidden.toggle() } },
            zoomed: { pose.isZoomed = $0 })
    }

    /// The chrome's fade, or none at all where somebody has asked for less movement.
    private var fade: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)
    }
}

#Preview("Viewer") {
    LibraryViewer(
        entries: MobilePreview.library().map(CachedEntry.init),
        opening: MobilePreview.library()[0].fileName
    )
    .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
    .environment(ReferenceIntent())
    .environment(MobileSelection())
}
