import Foundation

/// What can go wrong turning decoded pixels into a file, which is nothing about the model.
public enum PixelBufferError: Error, LocalizedError, Equatable {
    /// Image I/O refused to make a PNG of the pixels.
    case encodingFailed
    /// The decode came back with a channel count the packer has no layout for: three is a
    /// picture, four is one with transparency, and nothing else can be written four bytes to
    /// a pixel without lying about what the bytes mean.
    case unsupportedChannelCount(Int)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The decoded image could not be encoded as PNG."
        case .unsupportedChannelCount(let channels):
            "The decoded image has \(channels) channels, which is neither a picture nor a "
                + "picture with transparency."
        }
    }
}
