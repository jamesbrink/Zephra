import Foundation

/// What narrows the cached library: which collection, and what was typed.
///
/// The Mac's `LibraryQuery` cut down to the two axes a phone has. Pure, like the Mac's, and
/// for the same reason: the grid asks it what to draw and the chips ask it nothing, so the
/// view never filters and "does this picture belong on screen" is a question with a test.
nonisolated struct CachedLibraryQuery: Hashable, Sendable {
    /// The collection being looked at.
    var scope: CachedScope
    /// Free text, matched against the prompt, the tags, the seed and the model.
    var text: String

    /// A query over everything.
    init(scope: CachedScope = .all, text: String = "") {
        self.scope = scope
        self.text = text
    }

    /// What was typed, with the whitespace round it dropped; empty means no search.
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether one picture belongs in this query's results.
    func matches(_ entry: CachedEntry) -> Bool {
        guard matchesScope(entry) else { return false }
        let text = trimmedText
        guard !text.isEmpty else { return true }
        return entry.searchKey.contains(CachedEntry.folded(text))
    }

    /// The pictures this query names, newest first.
    ///
    /// Ties break on the file name, so a run of seeds that landed inside the same second is in
    /// a stable order rather than whichever order the folder happened to be read in.
    func matching(_ entries: [CachedEntry]) -> [CachedEntry] {
        entries.filter(matches).sorted { first, second in
            first.createdAt == second.createdAt
                ? first.fileName > second.fileName
                : first.createdAt > second.createdAt
        }
    }

    /// The pictures this query names, grouped into the days the grid shows them under, newest
    /// day first.
    func sections(of entries: [CachedEntry]) -> [CachedSection] {
        var order: [Date] = []
        var byDay: [Date: [CachedEntry]] = [:]
        for entry in matching(entries) {
            if byDay[entry.day] == nil { order.append(entry.day) }
            byDay[entry.day, default: []].append(entry)
        }
        return order.map { CachedSection(day: $0, entries: byDay[$0] ?? []) }
    }

    private func matchesScope(_ entry: CachedEntry) -> Bool {
        switch scope {
        case .all: true
        case .favourites: entry.isFavourite
        case .clips: entry.isVideo
        }
    }
}
