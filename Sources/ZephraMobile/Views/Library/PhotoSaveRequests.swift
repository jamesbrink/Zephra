import SwiftUI

/// Keeps a save's entry and cache lease alive even when the viewer pages elsewhere.
struct PhotoSaveRequests: ViewModifier {
    @Environment(LibraryCatalog.self) private var catalog
    @State private var status = Status()

    func body(content: Content) -> some View {
        content
            .environment(\.saveLibraryItem, save)
            .environment(\.photoSaveIsBusy, status.isSaving)
            .alert(status.succeeded ? "Saved to Photos" : "Couldn’t Save to Photos",
                isPresented: Binding(get: { status.message != nil }, set: { if !$0 { status.message = nil } })) {
                Button("OK", role: .cancel) { status.message = nil }
            } message: {
                Text(status.message ?? "")
            }
    }

    private struct Status {
        var isSaving = false
        var message: String?
        var succeeded = false
    }

    private func save(_ entry: CachedEntry) {
        guard !status.isSaving else { return }
        status.isSaving = true
        Task {
            defer { status.isSaving = false }
            let lease = await catalog.lease(entry)
            defer { withExtendedLifetime(lease) {} }
            do {
                let url = try await catalog.file(for: entry)
                try await PhotosSaver.save(url, isVideo: entry.isVideo)
                status.succeeded = true
                status.message = "Your \(entry.isVideo ? "video" : "image") was added to Photos."
            } catch {
                status.succeeded = false
                status.message = error.localizedDescription
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var photoSaveIsBusy = false
    @Entry var saveLibraryItem: (CachedEntry) -> Void = { _ in }
}
