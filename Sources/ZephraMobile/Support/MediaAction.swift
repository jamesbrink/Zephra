import Foundation
import Observation

@MainActor @Observable
final class MediaAction {
    private(set) var busy = false
    var message: String?
    var sharing: LeasedMedia?
    @ObservationIgnored private let save: (URL, Bool) async throws -> Void

    init(save: @escaping (URL, Bool) async throws -> Void = PhotosSaver.save) {
        self.save = save
    }

    func savePhoto(isVideo: Bool, fetch: () async throws -> LeasedMedia) async {
        guard !busy else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let media = try await fetch()
            defer { withExtendedLifetime(media) {} }
            try Task.checkCancellation()
            try await save(media.url, isVideo)
            try Task.checkCancellation()
            message = isVideo ? "Clip saved to Photos." : "Picture saved to Photos."
        } catch is CancellationError {} catch {
            if !Task.isCancelled { message = error.localizedDescription }
        }
    }

    func share(fetch: () async throws -> LeasedMedia) async {
        guard !busy, sharing == nil else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            let media = try await fetch()
            try Task.checkCancellation()
            sharing = media
        } catch is CancellationError {} catch {
            if !Task.isCancelled { message = error.localizedDescription }
        }
    }
}
