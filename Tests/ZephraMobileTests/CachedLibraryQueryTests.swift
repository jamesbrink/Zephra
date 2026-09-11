import Foundation
import Testing

@testable import ZephraMobile

/// What the library shows, which is the query's answer and never the view's.
@Suite("Narrowing the cached library")
struct CachedLibraryQueryTests {
    /// Three days of pictures: two today, one yesterday, one of them a favorite and one a clip.
    static let entries: [CachedEntry] = [
        LibraryFixtures.cached(
            "harbour.png", createdAt: day(0, hour: 9), prompt: "a harbour at first light",
            favourite: true, tags: ["rain"]),
        LibraryFixtures.cached(
            "bicycle.png", createdAt: day(0, hour: 11), prompt: "a red bicycle on a wall"),
        LibraryFixtures.cached(
            "dusk.png", createdAt: day(-1, hour: 18), prompt: "rain over a harbour at dusk",
            isVideo: true),
    ]

    @Test("All is everything, newest first")
    func allNewestFirst() {
        let sections = CachedLibraryQuery().sections(of: Self.entries)

        #expect(sections.count == 2)
        #expect(sections.first?.entries.map(\.fileName) == ["bicycle.png", "harbour.png"])
        #expect(sections.last?.entries.map(\.fileName) == ["dusk.png"])
        #expect(sections.first!.day > sections.last!.day, "newest day first")
    }

    @Test("Favorites is only what is marked")
    func favourites() {
        let query = CachedLibraryQuery(scope: .favourites)

        #expect(query.matching(Self.entries).map(\.fileName) == ["harbour.png"])
    }

    @Test("Clips is only what moves")
    func clips() {
        let query = CachedLibraryQuery(scope: .clips)

        #expect(query.matching(Self.entries).map(\.fileName) == ["dusk.png"])
    }

    @Test("Typing matches the prompt, folded, wherever it appears")
    func promptText() {
        let query = CachedLibraryQuery(text: "HARBOUR")

        #expect(Set(query.matching(Self.entries).map(\.fileName)) == ["harbour.png", "dusk.png"])
    }

    /// "rain" is a tag on one and a word in the other's prompt, and both are found: the search
    /// key is everything about a picture, not its prompt alone.
    @Test("Typing matches a tag, the model and the seed as well")
    func otherKeys() {
        #expect(
            Set(CachedLibraryQuery(text: "rain").matching(Self.entries).map(\.fileName))
                == ["harbour.png", "dusk.png"])
        #expect(CachedLibraryQuery(text: "z-image").matching(Self.entries).count == 2)
        let seed = Self.entries[1].entry.record.map { String($0.seed) } ?? ""
        #expect(CachedLibraryQuery(text: seed).matching(Self.entries).count >= 1)
    }

    @Test("A scope and a search narrow together")
    func both() {
        let query = CachedLibraryQuery(scope: .favourites, text: "bicycle")

        #expect(query.matching(Self.entries).isEmpty)
    }

    @Test("Whitespace alone is not a search")
    func blankText() {
        #expect(CachedLibraryQuery(text: "   ").matching(Self.entries).count == 3)
    }

    @Test("A day's heading says which day, and the scope says what it is counting")
    func headings() {
        let sections = CachedLibraryQuery().sections(of: Self.entries)

        #expect(sections.first?.title == "Today")
        #expect(sections.last?.title == "Yesterday")
        #expect(CachedScope.favourites.noun(1) == "favorite")
        #expect(CachedScope.all.noun(2) == "pictures")
        #expect(CachedScope.clips.noun(3) == "clips")
    }

    /// A date `offset` days from today at a fixed hour, so the headings are "Today" and
    /// "Yesterday" whenever the suite runs.
    static func day(_ offset: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? start
    }
}
