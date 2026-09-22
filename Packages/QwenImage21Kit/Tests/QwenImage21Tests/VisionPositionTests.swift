import Foundation
import MLX
import Testing

@testable import QwenImage21

/// Everything about *where* a reference picture's patches are: the block-major order they
/// arrive in, the learned position table's resampling onto that order, the tower's own axial
/// rotary, and the three-axis positions the decoder gives the picture's slots.
///
/// Each of these is a place a port can be wrong while loading cleanly and producing a plausible
/// picture of a different reference, so each is pinned against the reference's own arrays
/// rather than against this port's idea of the layout.
@Suite("A reference picture's patches land where the reference puts them")
struct VisionPositionTests {
    @Test("the tower's rotary theta is 10,000, which no shipped config states")
    func theVisionThetaIsPinned() throws {
        let fixture = try Fixture.load("vision")
        let theta = try #require(fixture["rope.real.theta"]).item(Float.self)
        #expect(Double(theta) == Qwen3VLVisionRotary.theta)

        // And the width the frequencies it makes rotate over: the published head is 72, half
        // of it spatial, so eighteen frequencies doubled twice. The buffer is non-persistent,
        // so the fixture above is the only place that theta is written down at all.
        let (cos, _) = Qwen3VLVisionRotary(try realVision()).tables(
            for: Qwen3VLImageGrid(rows: 2, columns: 2), dtype: .float32)
        #expect(cos.dim(1) == 72)
    }

    @Test("the rotary tables match the reference for the doll's grid and two published ones")
    func theRotaryTablesMatch() throws {
        let fixture = try Fixture.load("vision")
        for (label, configuration, grid) in try cases() {
            let rotary = Qwen3VLVisionRotary(configuration)
            let (cos, sin) = rotary.tables(for: grid, dtype: .float32)
            let cosError = Fixture.maxAbsoluteDifference(
                cos, try #require(fixture["vision.rope.\(label).cos"]))
            let sinError = Fixture.maxAbsoluteDifference(
                sin, try #require(fixture["vision.rope.\(label).sin"]))
            #expect(cosError < 1e-6, Comment(rawValue: "\(label) cos: \(cosError)"))
            #expect(sinError < 1e-6, Comment(rawValue: "\(label) sin: \(sinError)"))
        }
    }

    @Test("the patch order is block-major, so the four a merge combines are adjacent")
    func thePatchOrderIsBlockMajor() throws {
        let fixture = try Fixture.load("vision")
        for (label, configuration, grid) in try cases() {
            let reference = try #require(fixture["vision.positions.\(label)"])
            let ours = Qwen3VLPatchOrder.frameRepeated(
                grid, mergeSize: configuration.spatialMergeSize)
            let stacked = MLXArray(ours.flatMap { [Int32($0.row), Int32($0.column)] })
                .reshaped(ours.count, 2)
            #expect(
                Fixture.maxAbsoluteDifference(stacked, reference) == 0,
                Comment(rawValue: "\(label) patch order differs"))
        }
    }

    @Test("the position table is interpolated onto the grid, not sliced out of it")
    func thePositionTableIsInterpolated() throws {
        let fixture = try Fixture.load("vision")
        for (label, configuration, grid) in try cases() {
            let (indices, weights) = Qwen3VLVisionPositionEmbedding(configuration).taps(for: grid)
            let indexError = Fixture.maxAbsoluteDifference(
                indices, try #require(fixture["vision.interp.\(label).indices"]))
            let weightError = Fixture.maxAbsoluteDifference(
                weights, try #require(fixture["vision.interp.\(label).weights"]))
            // The indices are exact or they are the wrong rows of the table.
            #expect(indexError == 0, Comment(rawValue: "\(label) taps differ by \(indexError)"))
            #expect(weightError < 1e-6, Comment(rawValue: "\(label) weights: \(weightError)"))
        }
    }

    @Test("a picture's three-axis positions are the reference's, and the text resumes past it")
    func theThreeAxisPositionsMatch() throws {
        let fixture = try Fixture.load("vision")
        let configuration = try Qwen3VLDollHouse.configuration()
        let grid = Qwen3VLImageGrid(rows: 4, columns: 4)
        // The template's own shape: text, one `<|image_pad|>` per picture, text. The expansion
        // grows that one token into the picture's four slots, which is exactly the id run the
        // fixture was dumped over.
        let layout = try Qwen3VLTokenLayout(
            expanding: [1, 2, configuration.imageTokenID, 3, 4],
            imageTokenID: configuration.imageTokenID, grids: [grid], mergeSize: 2)
        let ids = try #require(fixture["joint.in.ids"]).asArray(Int32.self).map(Int.init)
        #expect(layout.ids == ids)
        #expect(layout.imageRuns == [2..<6])

        let positions = Qwen3VLPositionIDs.positions(
            layout: layout, grids: [grid], mergeSize: 2)
        let reference = try #require(fixture["joint.out.positions"]).squeezed(axis: 1)
        #expect(Fixture.maxAbsoluteDifference(positions, reference) == 0)
    }

    /// The fixture's three grids, each with the configuration it was dumped under.
    private func cases() throws -> [(String, Qwen3VLTextConfiguration.Vision, Qwen3VLImageGrid)] {
        let doll = try Qwen3VLDollHouse.configuration().vision
        let real = try realVision()
        return [
            ("doll.4x4", doll, Qwen3VLImageGrid(rows: 4, columns: 4)),
            ("real.6x8", real, Qwen3VLImageGrid(rows: 6, columns: 8)),
            ("real.32x32", real, Qwen3VLImageGrid(rows: 32, columns: 32)),
            // The grid a 1024-square reference picture lands on, which is what
            // `calculate_dimensions` brings every condition image to. Nothing above it was
            // pinned past 32 by 32 until the reference-conditioned parity suite went looking.
            ("real.64x64", real, Qwen3VLImageGrid(rows: 64, columns: 64)),
        ]
    }

    /// The published vision shape, spelled here because the release's own `config.json` is not
    /// on every Mac that runs this suite.
    private func realVision() throws -> Qwen3VLTextConfiguration.Vision {
        let json = """
            {"depth": 27, "hidden_size": 1152, "num_heads": 16, "intermediate_size": 4304,
             "in_channels": 3, "patch_size": 16, "temporal_patch_size": 2,
             "spatial_merge_size": 2, "num_position_embeddings": 2304, "out_hidden_size": 4096,
             "deepstack_visual_indexes": [8, 16, 24], "hidden_act": "gelu_pytorch_tanh"}
            """
        return try JSONDecoder().decode(
            Qwen3VLTextConfiguration.Vision.self, from: Data(json.utf8))
    }
}
