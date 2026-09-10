import Foundation
import MLX

/// T5's relative position bucketing, the bidirectional flavour an encoder uses.
///
/// Half the buckets go to each direction. Within a direction the first half count exact
/// distances and the second half are logarithmic bins up to `maxDistance`, beyond which every
/// distance shares the last bucket. The arithmetic is done in `Float` on purpose: the
/// reference computes the log ratio in float32 and truncates it to an integer, and a wider
/// type would round a distance sitting on a bin's edge into the other bin. `out.buckets` in
/// the fixture pins every distance a 512-token prompt can hold at the real model's numbers.
enum UMT5RelativePositionBucket {
    /// The bucket for `relativePosition`, key position minus query position.
    static func bucket(of relativePosition: Int, buckets numBuckets: Int, maxDistance: Int) -> Int {
        let perDirection = numBuckets / 2
        let direction = relativePosition > 0 ? perDirection : 0
        let distance = abs(relativePosition)
        let maxExact = perDirection / 2
        if distance < maxExact { return direction + distance }
        let ratio = log(Float(distance) / Float(maxExact)) / Float(log(Double(maxDistance) / Double(maxExact)))
        let large = maxExact + Int(ratio * Float(perDirection - maxExact))
        return direction + min(large, perDirection - 1)
    }

    /// The `[length, length]` table of buckets for every query and key position, in the
    /// layout every layer's bias table is gathered with: row is the query, column the key.
    static func table(length: Int, buckets numBuckets: Int, maxDistance: Int) -> MLXArray {
        var table = [Int32](repeating: 0, count: length * length)
        for query in 0..<length {
            for key in 0..<length {
                table[query * length + key] = Int32(
                    bucket(of: key - query, buckets: numBuckets, maxDistance: maxDistance))
            }
        }
        return MLXArray(table, [length, length])
    }
}
