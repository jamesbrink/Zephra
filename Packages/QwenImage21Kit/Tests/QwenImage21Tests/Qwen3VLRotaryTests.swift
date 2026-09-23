import Foundation
import MLX
import Testing

@testable import QwenImage21

/// Interleaved MRoPE against the reference's own tables, at the doll's-house width and at the
/// published one.
///
/// Three claims, and each is a mistake that compiles: which half-dim reads which position axis,
/// that the tables are doubled and rotated with `rotate_half` rather than adjacent pairs, and
/// that a text-only prompt — three identical rows — collapses to plain 1-D rope with theta five
/// million, which is what lets the text path take the cheap route without a second
/// implementation.
@Suite("Interleaved MRoPE is the reference's, and text-only collapses to plain rope")
struct Qwen3VLRotaryTests {
    @Test(
        "the published section gives the row axis 1, 4, ..., 58 and the column axis 2, 5, ..., 59")
    func theSectionIsInterleaved() {
        let section = [24, 20, 20]
        let axes = (0..<64).map { Qwen3VLRotary.axis(ofHalfDim: $0, mropeSection: section) }

        #expect(axes.indices.filter { axes[$0] == 1 } == Array(stride(from: 1, to: 60, by: 3)))
        #expect(axes.indices.filter { axes[$0] == 2 } == Array(stride(from: 2, to: 60, by: 3)))
        // Time keeps 0, 3, ..., 57 — and then the last four, which is where its 24 against the
        // others' 20 comes from and the one part the word "interleaved" does not describe.
        #expect(axes.indices.filter { axes[$0] == 0 }.suffix(4) == [60, 61, 62, 63])
        #expect(axes.filter { $0 == 0 }.count == 24)
    }

    @Test("the tables match the reference at both widths, text-only and three-axis")
    func theTablesMatchTheReference() throws {
        let fixture = try Fixture.load("text_encoder")
        let published = Qwen3VLRotary(headDim: 128, theta: 5_000_000, mropeSection: [24, 20, 20])
        let doll = Qwen3VLRotary(headDim: 8, theta: 5_000_000, mropeSection: [2, 1, 1])

        for (name, rotary) in [("real", published), ("doll", doll)] {
            for run in ["text", "threeAxis"] {
                let positions = try #require(fixture["rope.\(name).\(run).positions"])
                let (cos, sin) = rotary.tables(positions: positions, dtype: .float32)
                let cosError = Fixture.maxAbsoluteDifference(
                    cos, try #require(fixture["rope.\(name).\(run).cos"]))
                let sinError = Fixture.maxAbsoluteDifference(
                    sin, try #require(fixture["rope.\(name).\(run).sin"]))
                #expect(cosError < 1e-6, Comment(rawValue: "\(name).\(run) cos: \(cosError)"))
                #expect(sinError < 1e-6, Comment(rawValue: "\(name).\(run) sin: \(sinError)"))
            }
        }
    }

    @Test("with all three rows equal it is plain 1-D rope, every channel on the same angle")
    func textOnlyCollapsesToPlainRope() {
        let rotary = Qwen3VLRotary(headDim: 128, theta: 5_000_000, mropeSection: [24, 20, 20])
        let (cos, _) = rotary.tables(positions: Qwen3VLRotary.textPositions(count: 9), dtype: .float32)

        // Plain rope written out: angle = position * theta^(-2i/dim), doubled.
        let frequencies: [Double] = (0..<64).map { half in
            let exponent: Double = -Double(2 * half) / 128
            return pow(5_000_000 as Double, exponent)
        }
        var angles: [Float] = []
        for position in 0..<9 {
            for frequency in frequencies {
                angles.append(Float(Foundation.cos(Double(position) * frequency)))
            }
        }
        let plain = MLX.concatenated(
            [MLXArray(angles).reshaped(9, 64), MLXArray(angles).reshaped(9, 64)], axis: -1)
        let difference = Fixture.maxAbsoluteDifference(cos, plain)
        #expect(difference < 1e-6, Comment(rawValue: "text-only rope differs by \(difference)"))
    }

    @Test("rotate_half pairs a channel with the one half a head away, not with its neighbour")
    func theRotationIsTheHalfSplit() {
        let x = MLXArray((0..<8).map { Float($0) }).reshaped(1, 1, 1, 8)
        let rotated = Qwen3VLRotary.rotateHalf(x)
        #expect(rotated.reshaped(8).asArray(Float.self) == [-4, -5, -6, -7, 0, 1, 2, 3])
    }
}
