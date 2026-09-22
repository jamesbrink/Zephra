import Foundation

/// What a kit's preview frame has to be for the engine to draw it: pixels and their size.
///
/// Each family's `<Family>LatentPreview` is its own struct with exactly these three fields, and
/// this is the one shape a backend has to declare it fits — a one-line conformance — for
/// `PreviewFrameReporter` to carry it up as a `GenerationPreview`. A protocol rather than a
/// shared struct because the vendored kit's frame cannot be changed to be one.
public protocol PreviewFrame {
    /// Pixels across.
    var width: Int { get }
    /// Pixels down.
    var height: Int { get }
    /// `width * height * 4` bytes, RGBA8, row-major, straight alpha; 255 everywhere for a
    /// model that makes no transparency.
    var pixels: Data { get }
}
