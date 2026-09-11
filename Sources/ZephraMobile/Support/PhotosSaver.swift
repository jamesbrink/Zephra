import Foundation
import Photos
import os

/// Putting one of the Mac's pictures in the phone's own photo library.
///
/// `.addOnly` authorization, and only that: Zephra never reads anybody's camera roll, and
/// asking for the read scope would put a far more alarming question in front of somebody who
/// only wanted to keep a picture. iOS remembers the answer, so the question is asked once.
///
/// A file URL rather than the bytes. `PHAssetCreationRequest` reads the file itself, which
/// keeps a forty-megabyte clip off the heap, and it is the only way the video case works at
/// all — the photo library wants a movie file, not a buffer.
nonisolated enum PhotosSaver {
    /// What went wrong, in the words to put on screen.
    enum Failure: LocalizedError {
        /// Somebody said no, or a restriction says no for them.
        case notAllowed
        /// The photo library refused the file.
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .notAllowed:
                "Zephra has not been allowed to add to your photo library. "
                    + "Settings > Privacy & Security > Photos can change that."
            case .refused(let reason): reason
            }
        }
    }

    /// Saves one picture or clip, asking for permission the first time.
    ///
    /// - Parameters:
    ///   - url: the file on this phone, which is what the cache hands back.
    ///   - isVideo: whether the photo library should take it as a movie.
    static func save(_ url: URL, isVideo: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
            }
        } catch {
            Logger(subsystem: "io.zephra", category: "mobile.photos")
                .notice("The photo library refused a file: \(error.localizedDescription)")
            throw Failure.refused(error.localizedDescription)
        }
    }
}
