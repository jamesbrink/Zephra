import MLX
import MLXNN

/// What a pass that stopped part way leaves behind.
///
/// A pass that throws — Stop between blocks, or a GPU fault that cancelled the run — has not
/// released the layers from the throw point on. Those still hold this pass's nodes, some of
/// them prefetched, and after a fault whose command buffers were discarded a node can be
/// marked evaluated over a buffer that never received its bytes. The store reruns such a job
/// at once, so the first step of that rerun would read whatever the buffer held. Pointing
/// every layer not yet released at the next pass's fresh, unevaluated nodes makes the next
/// pass read its weights off the disk again, exactly as an uninterrupted one would.
extension LayerWeightStream {
    /// Re-points every layer from `first` on at `next`'s nodes. A tensor already taken for a
    /// layer released part way is skipped rather than thrown over: the error being handled is
    /// the one worth reporting, and that layer's other slots still want their fresh nodes.
    func recover(from first: Int, using next: inout [String: MLXArray]) {
        for position in first..<slots.count {
            for slot in slots[position] {
                guard let fresh = next.removeValue(forKey: slot.checkpointKey) else { continue }
                slot.array._updateInternal(fresh.dtype == slot.dtype ? fresh : fresh.asType(slot.dtype))
            }
        }
    }
}
