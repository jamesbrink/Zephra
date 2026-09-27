import SwiftUI

/// The presenting surface owns save state and the operation owns its media lease.
struct PhotoSaveRequests: ViewModifier {
    @Environment(LibraryCatalog.self) private var catalog
    @State private var action = MediaAction()

    func body(content: Content) -> some View {
        content
            .environment(\.saveLibraryItem, save)
            .environment(\.photoSaveIsBusy, action.busy)
            .modifier(MediaActionFeedback(action: action))
    }

    private func save(_ entry: CachedEntry) {
        Task {
            await action.savePhoto(isVideo: entry.isVideo) {
                try await catalog.leasedMedia(for: entry)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var photoSaveIsBusy = false
    @Entry var saveLibraryItem: (CachedEntry) -> Void = { _ in }
}
