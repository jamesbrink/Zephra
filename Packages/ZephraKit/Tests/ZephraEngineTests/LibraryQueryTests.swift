import Foundation
import Testing

@testable import ZephraEngine

@Suite("LibraryQuery")
struct LibraryQueryTests {
    @Test("a query over everything shows no tokens")
    func emptyQueryHasNoTokens() {
        let query = LibraryQuery()
        #expect(query.tokens.isEmpty)
        #expect(!query.isNarrowed)
    }

    @Test("a scope, a model, a tag, and a search each become one token, in reading order")
    func tokensReadInOrder() {
        let query = LibraryQuery(
            scope: .favourites, text: "  bicycle ", modelID: "qwen-image-2512-4bit", tag: "keep")
        #expect(query.tokens == [
            .scope(.favourites), .model("qwen-image-2512-4bit"), .tag("keep"), .search("bicycle"),
        ])
    }

    @Test("removing one token leaves the others alone")
    func removingATokenIsLocal() {
        let query = LibraryQuery(scope: .favourites, text: "bicycle", tag: "keep", sort: .oldestFirst)
        let without = query.removing(.search("bicycle"))
        #expect(without.text.isEmpty)
        #expect(without.scope == .favourites)
        #expect(without.tag == "keep")
        #expect(without.sort == .oldestFirst, "the sort is never a token")
        #expect(query.removing(.scope(.favourites)).scope == .all)
    }

    @Test("whitespace-only search text is not a search")
    func whitespaceIsNotASearch() {
        #expect(LibraryQuery(text: "   ").tokens.isEmpty)
    }

    @Test("a scope round-trips through its stable spelling, album identity included")
    func scopeRoundTrips() {
        let id = UUID()
        let scopes: [LibraryScope] = [
            .all, .favourites, .lastSevenDays, .album(id), .recentlyDeleted, .sources,
        ]
        for scope in scopes {
            #expect(LibraryScope(rawValue: scope.rawValue) == scope)
        }
        #expect(LibraryScope(rawValue: "album:not-a-uuid") == nil)
        #expect(LibraryScope(rawValue: "somewhere-else") == nil)
    }
}
