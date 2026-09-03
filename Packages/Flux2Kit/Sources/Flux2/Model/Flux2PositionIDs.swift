import Foundation

/// Where every token sits, on the four axes the rotary embedding reads.
///
/// The axes are image index, row, column, and text position. A text token is `[0, 0, 0, l]`
/// and the image being made is `[0, h, w, 0]`, so the two never share a coordinate on the axis
/// the other varies along. A reference image handed in for editing gets its own index on the
/// first axis, at its own rows and columns, so it can be any size at all.
///
/// Rows and columns count from zero. Qwen-Image centres them; FLUX.2 does not, and the two
/// conventions produce different images from the same seed.
public enum Flux2PositionIDs {
    /// One id per text position.
    public static func text(count: Int) -> [[Int]] {
        (0..<count).map { [0, 0, 0, $0] }
    }

    /// One id per image token, row-major, at image index `imageIndex`.
    ///
    /// Row-major is the order the packed tokens arrive in; see `Flux2LatentPacking.tokens`.
    public static func image(height: Int, width: Int, imageIndex: Int = 0) -> [[Int]] {
        var ids: [[Int]] = []
        ids.reserveCapacity(height * width)
        for row in 0..<height {
            for column in 0..<width {
                ids.append([imageIndex, row, column, 0])
            }
        }
        return ids
    }

    /// The image index for the `index`th reference image. The image being made is 0; the
    /// reference's are spaced ten apart from it and from each other, as the reference does.
    public static func referenceImageIndex(_ index: Int) -> Int {
        10 * (index + 1)
    }
}
