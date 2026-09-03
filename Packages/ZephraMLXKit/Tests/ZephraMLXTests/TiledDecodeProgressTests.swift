import Foundation
import MLX
import Testing

@testable import ZephraMLX

/// The two things a caller driving progress and cancellation relies on: the tile count it is
/// told matches the tiles that run, and a decoder that throws stops the run where it threw.
@Suite("Tiled decode progress")
struct TiledDecodeProgressTests {
    private struct Stop: Error {}

    @Test("the tile count announced up front is the number of tiles that run")
    func countMatchesTheRun() {
        let latents = MLXArray.zeros([1, 20, 30, 4])
        var seen: [(Int, Int)] = []
        _ = TiledDecode.run(latents, tile: 16, scale: 2, onTile: { seen.append(($0, $1)) }) {
            let (height, width) = ($0.dim(1), $0.dim(2))
            return MLX.broadcast(
                $0[0..., 0..., 0..., 0..<3].reshaped([1, height, 1, width, 1, 3]),
                to: [1, height, 2, width, 2, 3]
            ).reshaped([1, height * 2, width * 2, 3])
        }
        // 20 by 30 on a stride of 12 is 2 rows of 3.
        #expect(TiledDecode.tileCount(height: 20, width: 30, tile: 16) == 6)
        #expect(seen.map(\.0) == [1, 2, 3, 4, 5, 6])
        #expect(seen.allSatisfy { $0.1 == 6 })
    }

    @Test("a decoder that throws stops the run at that tile")
    func throwingStopsTheRun() {
        let latents = MLXArray.zeros([1, 20, 30, 4])
        var ran = 0
        #expect(throws: Stop.self) {
            try TiledDecode.run(latents, tile: 16, scale: 1) { patch in
                ran += 1
                if ran == 3 { throw Stop() }
                return patch[0..., 0..., 0..., 0..<3]
            }
        }
        #expect(ran == 3)
    }

    @Test("a tile at least as large as the input counts as one")
    func oneTileCountsOnce() {
        #expect(TiledDecode.tileCount(height: 8, width: 8, tile: 16) == 1)
        #expect(TiledDecode.tileCount(height: 0, width: 8, tile: 16) == 0)
    }
}
