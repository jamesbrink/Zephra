import SwiftUI

/// Preserve a visible picture while density changes instead of jumping to another day.
struct GalleryScroll<Content: View>: View {
    let content: Content
    @Environment(\.galleryColumns) private var columns
    @State private var position = GalleryScrollPosition()
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { ids in
                    position.visible = ids.first
                }
                .onChange(of: columns) {
                    if let id = position.visible { position.anchor = id }
                    if let id = position.anchor { proxy.scrollTo(id, anchor: .top) }
                }
        }
    }
}
