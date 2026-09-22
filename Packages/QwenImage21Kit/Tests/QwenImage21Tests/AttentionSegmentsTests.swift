import Foundation
import MLX
import Testing

@testable import QwenImage21

@Suite("The prefix splits into the attention calls the block-causal mask implies")
struct AttentionSegmentsTests {
    @Test("the segment boundaries are the reference's")
    func boundaries() throws {
        let fixture = try Fixture.load("rope")
        let expected = try Fixture.load("segments")
        for label in JointLayoutFixture.labels {
            let layout = try JointLayoutFixture.layout(label, in: fixture)
            let flat = try Fixture.ints(expected, "\(label).segments")
            let reference = stride(from: 0, to: flat.count, by: 3).map {
                QwenImage21AttentionSegments.Segment(
                    start: flat[$0], end: flat[$0 + 1], isText: flat[$0 + 2] != 0)
            }
            #expect(
                QwenImage21AttentionSegments(layout).segments == reference,
                Comment(rawValue: "\(label)'s segments"))
        }
    }

    /// The claim the decomposition rests on: the keys each segment is allowed are exactly the
    /// keys `(q >= kv) or same image block` allows, so the several unmasked or causal calls and
    /// one dense masked call attend over the same set. The dense rule here is the reference's
    /// `mask_mod`, written out.
    @Test("the segments allow exactly what the block-causal rule allows")
    func segmentsCoverTheSameKeys() throws {
        let fixture = try Fixture.load("rope")
        for label in JointLayoutFixture.labels {
            let layout = try JointLayoutFixture.layout(label, in: fixture)
            let ids = layout.imageIDs
            let length = layout.sequenceLength

            var allowed = [[Bool]](
                repeating: [Bool](repeating: false, count: length), count: length)
            for segment in QwenImage21AttentionSegments(layout).segments {
                for query in segment.start..<segment.end {
                    // A text run is causal within itself; an image run is bidirectional. Both
                    // see everything before the run.
                    let last = segment.isText ? query : segment.end - 1
                    for key in 0...last { allowed[query][key] = true }
                }
            }
            for query in layout.prefixLength..<length {
                for key in 0..<length { allowed[query][key] = true }
            }

            let mismatched = (0..<length).flatMap { query in
                (0..<length).filter { key in
                    let sameBlock = ids[query] == ids[key] && ids[query] >= 0
                    return allowed[query][key] != (query >= key || sameBlock)
                }.map { "(\(query), \($0))" }
            }
            #expect(mismatched.isEmpty, Comment(rawValue: "\(label): \(mismatched.prefix(8))"))
        }
    }
}
