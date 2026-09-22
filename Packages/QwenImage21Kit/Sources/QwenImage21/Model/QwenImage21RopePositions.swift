import Foundation

/// Where every joint token sits on the three rotary axes: frame, row, column.
///
/// A **text** token at joint position `i` gets `(p, p, p)` for a counter that advances one per
/// text token. An **image block** freezes the frame axis at the `p` the preceding text reached
/// and lays its tokens out on a zero-centred raster grid — rows `-(H - H/2) ..< H/2`, columns
/// `-(W - W/2) ..< W/2`, row-major with `W` columns per row. After a block the counter advances
/// by `max(H, W)`, **not** by `H * W`.
///
/// Two consequences are worth stating because a port that misses either still makes a picture.
/// A block's spatial positions do not depend on where in the sequence it sits, so two condition
/// images get the same centred grid and are told apart only by the frame axis and the attention
/// mask. And the row and column axes go **negative**, which the reference reads out of a table
/// whose tail holds positions −1024 to −1; this port computes the angle from the position
/// directly, which is the same number and needs no wrap.
public struct QwenImage21RopePositions: Sendable {
    /// One frame position per joint token.
    public let frame: [Int]
    /// One row position per joint token.
    public let height: [Int]
    /// One column position per joint token.
    public let width: [Int]

    /// How many tokens these positions cover.
    public var count: Int { frame.count }

    /// Positions stated outright, for a caller that has them already.
    public init(frame: [Int], height: [Int], width: [Int]) {
        self.frame = frame
        self.height = height
        self.width = width
    }

    /// Assigns positions over `layout`'s joint sequence.
    public init(_ layout: QwenImage21JointLayout) {
        let pad = layout.imagePadMask
        var frames: [Int] = []
        var rows: [Int] = []
        var columns: [Int] = []
        frames.reserveCapacity(pad.count)

        var cursor = 0
        var position = 0
        for shape in layout.shapes {
            // The next run of latents; everything between here and it is text.
            guard let blockStart = (cursor..<pad.count).first(where: { pad[$0] }) else { break }
            frames.append(contentsOf: position..<(position + blockStart - cursor))
            position += blockStart - cursor

            // The reference counts a block's extent as `height * width`, not as `tokenCount`.
            // The two agree at one frame, which is every entry 2.1 ships.
            let extent = shape.height * shape.width
            cursor = blockStart + extent
            frames.append(contentsOf: repeatElement(position, count: extent))
            position += shape.frameAdvance

            let rowRange = -(shape.height - shape.height / 2)..<(shape.height / 2)
            let columnRange = -(shape.width - shape.width / 2)..<(shape.width / 2)
            rows.append(contentsOf: rowRange.flatMap { repeatElement($0, count: shape.width) })
            columns.append(contentsOf: (0..<shape.height).flatMap { _ in columnRange })
        }
        if cursor < pad.count {
            frames.append(contentsOf: position..<(position + pad.count - cursor))
        }

        // The height and width axes are the frame axis everywhere but at a latent, where the
        // centred grid replaces it.
        var heights = frames
        var widths = frames
        var consumed = 0
        for index in pad.indices where pad[index] {
            heights[index] = rows[consumed]
            widths[index] = columns[consumed]
            consumed += 1
        }
        frame = frames
        height = heights
        width = widths
    }
}
