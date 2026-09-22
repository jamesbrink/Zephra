import Foundation
import MLX
import Testing

@testable import QwenImage21

/// The three joint layouts `Tools/dump_rope.py` dumped, by the names it wrote them under.
///
/// The grids are stated here and the slot masks come out of the fixture, so a suite is always
/// reading the mask the reference was actually handed rather than one rebuilt beside it.
enum JointLayoutFixture {
    /// The doll's-house rotary split: three axes filling one head of sixteen.
    static let axesDim = [4, 6, 6]

    /// Every layout's grids, condition images first and the target last.
    static let shapes: [String: [QwenImage21ImageShape]] = [
        "target": [QwenImage21ImageShape(height: 3, width: 4)],
        "edit": [
            QwenImage21ImageShape(height: 2, width: 4), QwenImage21ImageShape(height: 3, width: 4),
        ],
        "twoConditions": [
            QwenImage21ImageShape(height: 2, width: 2), QwenImage21ImageShape(height: 2, width: 4),
            QwenImage21ImageShape(height: 3, width: 4),
        ],
    ]

    /// The names, in the order they are worth reading a failure in.
    static let labels = ["target", "edit", "twoConditions"]

    /// One layout, built from the fixture's own slot mask.
    static func layout(_ label: String, in fixture: [String: MLXArray]) throws
        -> QwenImage21JointLayout
    {
        try QwenImage21JointLayout(
            imageSlots: try Fixture.flags(fixture, "\(label).imgMask"),
            shapes: try #require(shapes[label]))
    }
}
