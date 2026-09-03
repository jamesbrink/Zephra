import Foundation

/// Everything that narrows the library, in one value.
///
/// Both panes read it and only the sidebar writes it, so a search typed on the canvas and the
/// grid it opens are looking at the same thing. Two axes: `scope` is the collection being
/// looked at, and the rest are filters over it.
public struct LibraryQuery: Hashable, Sendable {
    /// The collection being looked at.
    public var scope: LibraryScope
    /// Free text matched against prompts, seeds, file names, and tags; empty matches everything.
    public var text: String
    /// Only images made by this model, by descriptor identifier; nil for any model.
    public var modelID: String?
    /// Only images carrying this tag; nil for any.
    public var tag: String?
    /// The order the matches are listed in.
    public var sort: LibrarySort

    /// A query over everything, newest first.
    public init(
        scope: LibraryScope = .all,
        text: String = "",
        modelID: String? = nil,
        tag: String? = nil,
        sort: LibrarySort = .newestFirst
    ) {
        self.scope = scope
        self.text = text
        self.modelID = modelID
        self.tag = tag
        self.sort = sort
    }

    /// The search text with surrounding whitespace dropped; empty means no search.
    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether anything at all narrows the library.
    public var isNarrowed: Bool { !tokens.isEmpty }

    /// The removable tokens the filter bar shows, in the order they read: where you are, then
    /// what narrows it, then what you typed.
    public var tokens: [LibraryQueryToken] {
        var tokens: [LibraryQueryToken] = []
        if scope != .all { tokens.append(.scope(scope)) }
        if let modelID { tokens.append(.model(modelID)) }
        if let tag { tokens.append(.tag(tag)) }
        if !trimmedText.isEmpty { tokens.append(.search(trimmedText)) }
        return tokens
    }

    /// The same query without one token. Removing the scope goes back to everything; the sort
    /// is never a token, so it is never removed.
    public func removing(_ token: LibraryQueryToken) -> LibraryQuery {
        var query = self
        switch token {
        case .scope: query.scope = .all
        case .model: query.modelID = nil
        case .tag: query.tag = nil
        case .search: query.text = ""
        }
        return query
    }
}
