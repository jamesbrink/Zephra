import Foundation

/// Moving the selection with the keyboard.
///
/// Left and right walk the flat reading order, so they cross a day heading without ceremony. Up
/// and down move by a row within a day, and step into the day above or below at the same column
/// when there is no row left — clamped to that day's count, because the last day of a month may
/// hold two images and the column may be the fifth.
extension LibraryCursor {
    /// Where the selection goes, or nil when it cannot go anywhere.
    public static func move(
        _ direction: Direction,
        in sections: [LibrarySection],
        columns: Int,
        selection: Set<LibraryItem.ID>,
        anchor: LibraryItem.ID?,
        extending: Bool = false
    ) -> Outcome? {
        let flat = order(of: sections)
        guard !flat.isEmpty else { return nil }
        // While extending, the end that moves is the one away from the anchor: the anchor is
        // where the selection is pinned, and the cursor is the other end of the run.
        let from = extending
            ? cursor(of: selection, in: flat, anchor: anchor)
            : anchor.flatMap { flat.firstIndex(of: $0) }
        guard let to = destination(direction, from: from, in: sections, columns: max(1, columns)),
              to != from
        else { return nil }
        let id = flat[to]
        guard extending, let anchor, flat.contains(anchor) else {
            return Outcome(ids: [id], anchor: id, reveal: id)
        }
        // The anchor stays put and the selection is the run between it and where the cursor now
        // is, exactly as a shift-click behaves: three shift-downs and then a shift-up leaves two
        // rows selected rather than four, because the selection shrinks back the way it grew.
        return Outcome(ids: range(from: anchor, to: id, in: flat), anchor: anchor, reveal: id)
    }

    /// Where the moving end of a shift-selection currently is: the selected image furthest from
    /// the anchor. A selection that is not a run from the anchor — built with the command key —
    /// falls back to its last image, which is where a sweep would have left off.
    private static func cursor(
        of selection: Set<LibraryItem.ID>,
        in flat: [LibraryItem.ID],
        anchor: LibraryItem.ID?
    ) -> Int? {
        guard let anchor, let anchored = flat.firstIndex(of: anchor) else { return nil }
        var first: Int?
        var last: Int?
        for (index, id) in flat.enumerated() where selection.contains(id) {
            if first == nil { first = index }
            last = index
        }
        guard let first, let last else { return anchored }
        return anchored == first ? last : first
    }

    /// The flat index the move lands on, or nil when there is nowhere to go.
    private static func destination(
        _ direction: Direction,
        from: Int?,
        in sections: [LibrarySection],
        columns: Int
    ) -> Int? {
        let counts = sections.map(\.items.count)
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }
        guard let from else {
            // Nothing is selected yet: any move puts the cursor at one end or the other.
            switch direction {
            case .left, .up, .end: return total - 1
            case .right, .down, .home: return 0
            }
        }
        switch direction {
        case .home: return 0
        case .end: return total - 1
        case .left: return max(0, from - 1)
        case .right: return min(total - 1, from + 1)
        case .up, .down: return byRow(direction, from: from, counts: counts, columns: columns)
        }
    }

    /// A row's worth of movement inside a day, or a step into the day next to it.
    private static func byRow(
        _ direction: Direction,
        from: Int,
        counts: [Int],
        columns: Int
    ) -> Int? {
        var start = 0
        var section = 0
        while section < counts.count, from >= start + counts[section] {
            start += counts[section]
            section += 1
        }
        guard section < counts.count else { return nil }
        let inSection = from - start
        let column = inSection % columns
        if direction == .down {
            if inSection + columns < counts[section] { return from + columns }
            // A day with nothing in it has no cell to land on. Nothing produces one today, but
            // clamping to a count of zero would land on the row above's last image.
            guard section + 1 < counts.count, counts[section + 1] > 0 else { return nil }
            return start + counts[section] + min(column, counts[section + 1] - 1)
        }
        if inSection >= columns { return from - columns }
        guard section > 0, counts[section - 1] > 0 else { return nil }
        let previous = counts[section - 1]
        let lastRow = ((previous - 1) / columns) * columns
        return start - previous + min(lastRow + column, previous - 1)
    }
}
