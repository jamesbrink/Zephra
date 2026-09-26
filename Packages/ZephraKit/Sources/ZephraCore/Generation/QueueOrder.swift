import Foundation

/// Pure whole-batch ordering used by both interfaces.
public enum QueueOrder {
    public static func moving(_ id: UUID, before target: UUID?, in order: [UUID]) -> [UUID] {
        guard order.contains(id), id != target, target == nil || order.contains(target!) else { return order }
        var next = order.filter { $0 != id }
        let index = target.flatMap { next.firstIndex(of: $0) } ?? next.count
        next.insert(id, at: index)
        return next
    }
    public static func adjacent(_ id: UUID, earlier: Bool, in order: [UUID]) -> [UUID] {
        guard let index = order.firstIndex(of: id) else { return order }
        let other = index + (earlier ? -1 : 1)
        guard order.indices.contains(other) else { return order }
        var next = order; next.swapAt(index, other); return next
    }
}
