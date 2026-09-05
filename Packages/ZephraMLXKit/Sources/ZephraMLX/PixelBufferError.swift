import Foundation

/// What can go wrong turning decoded pixels into a file, which is nothing about the model.
public enum PixelBufferError: Error, LocalizedError, Equatable {
    /// Image I/O refused to make a PNG of the pixels.
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The decoded image could not be encoded as PNG."
        }
    }
}
