import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Narrowing the library: what a scope shows, what typing finds, and how days are cut.
@Suite("Narrowing the library")
struct LibraryFilteringTests {
    static let now = Date(timeIntervalSince1970: 1_772_000_000)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test("typing finds the prompt, either spelling of the seed, and a tag")
    func textMatches() {
        let item = Self.item(
            prompt: "A café in Montmartre", seed: 0xABCD_1234_5678_9ABC, tags: ["night"])
        #expect(Self.query(text: "montmartre").matches(item, now: Self.now))
        #expect(Self.query(text: "CAFE").matches(item, now: Self.now), "diacritics and case fold")
        #expect(Self.query(text: "café").matches(item, now: Self.now))
        #expect(Self.query(text: "12379570966709705404").matches(item, now: Self.now), "decimal seed")
        #expect(Self.query(text: "ABCD·1234").matches(item, now: Self.now), "the label on screen")
        #expect(Self.query(text: "night").matches(item, now: Self.now), "a tag")
        #expect(Self.query(text: "  ").matches(item, now: Self.now), "whitespace narrows nothing")
        #expect(!Self.query(text: "harbour").matches(item, now: Self.now))
    }

    @Test("each scope shows its own collection and nothing else")
    func scopes() {
        let album = UUID()
        let plain = Self.item(prompt: "plain")
        let favourite = Self.item(prompt: "liked", favourite: true)
        let old = Self.item(prompt: "old", at: Self.now.addingTimeInterval(-30 * 86_400))
        let member = Self.item(prompt: "in an album", albums: [(album, "Harbours")])
        let deleted = Self.item(prompt: "deleted", collection: .recentlyDeleted)
        let source = Self.item(prompt: "imported", collection: .sources)
        let all = [plain, favourite, old, member, deleted, source]

        func prompts(_ scope: LibraryScope) -> [String] {
            LibraryQuery(scope: scope).matching(all, now: Self.now).map(\.prompt)
        }
        #expect(Set(prompts(.all)) == ["plain", "liked", "old", "in an album"])
        #expect(prompts(.favourites) == ["liked"])
        #expect(Set(prompts(.lastSevenDays)) == ["plain", "liked", "in an album"])
        #expect(prompts(.album(album)) == ["in an album"])
        #expect(prompts(.album(UUID())).isEmpty)
        #expect(prompts(.recentlyDeleted) == ["deleted"])
        #expect(prompts(.sources) == ["imported"])
    }

    @Test("a model and a tag narrow together, and a scope narrows both")
    func filtersCompose() {
        let wanted = Self.item(prompt: "wanted", favourite: true, tags: ["rain"])
        let otherModel = Self.item(prompt: "other model", modelID: "another-model", tags: ["rain"])
        let otherTag = Self.item(prompt: "other tag", tags: ["sun"])
        let notFavourite = Self.item(prompt: "not liked", tags: ["rain"])
        let all = [wanted, otherModel, otherTag, notFavourite]

        var query = LibraryQuery(modelID: ModelCatalog.default.id, tag: "rain")
        #expect(Set(query.matching(all, now: Self.now).map(\.prompt)) == ["wanted", "not liked"])
        query.scope = .favourites
        #expect(query.matching(all, now: Self.now).map(\.prompt) == ["wanted"])
        query.text = "nothing like this"
        #expect(query.matching(all, now: Self.now).isEmpty)
    }

    @Test("both sorts run, and the days are cut at local midnight")
    func sectionsAndSorts() {
        let day = Self.calendar.startOfDay(for: Self.now)
        let lateOnTheFirstDay = Self.item(prompt: "23:30", at: day.addingTimeInterval(84_600))
        let justAfterMidnight = Self.item(prompt: "00:30", at: day.addingTimeInterval(88_200))
        let items = [justAfterMidnight, lateOnTheFirstDay]

        let newest = LibraryQuery(sort: .newestFirst).sections(of: items, now: Self.now)
        #expect(newest.map { $0.items.map(\.prompt) } == [["00:30"], ["23:30"]])
        #expect(newest.first?.day == day.addingTimeInterval(86_400))

        let oldest = LibraryQuery(sort: .oldestFirst).sections(of: items, now: Self.now)
        #expect(oldest.map { $0.items.map(\.prompt) } == [["23:30"], ["00:30"]])
        #expect(oldest.first?.day == day)
    }

    @Test("the counts say what each sidebar row would show")
    func counts() {
        let album = UUID()
        let empty = UUID()
        let items = [
            Self.item(prompt: "one", favourite: true, tags: ["rain"], albums: [(album, "Harbours")]),
            Self.item(prompt: "two", modelID: "another-model", tags: ["rain", "night"]),
            Self.item(prompt: "old", at: Self.now.addingTimeInterval(-30 * 86_400)),
            Self.item(prompt: "deleted", collection: .recentlyDeleted),
            Self.item(prompt: "imported", collection: .sources),
        ]

        let counts = LibraryCounts(items: items, albumIDs: [album, empty], now: Self.now)
        #expect(counts.total == 3)
        #expect(counts.favourites == 1)
        #expect(counts.lastSevenDays == 2)
        #expect(counts.recentlyDeleted == 1)
        #expect(counts.sources == 1)
        #expect(counts.perModel == [ModelCatalog.default.id: 2, "another-model": 1])
        #expect(counts.perTag == ["rain": 2, "night": 1])
        #expect(counts.perAlbum == [album: 1, empty: 0], "an empty album still has a row")
        #expect(counts.count(for: .favourites) == 1)
        #expect(counts.count(for: .album(empty)) == 0)
        #expect(LibraryCounts.empty.total == 0)
    }

    /// An item with no file behind it: everything these tests ask about is in the value.
    static func item(
        prompt: String,
        seed: UInt64 = 42,
        at created: Date = LibraryFilteringTests.now,
        modelID: String = ModelCatalog.default.id,
        collection: LibraryCollection = .generated,
        favourite: Bool = false,
        tags: [String] = [],
        albums: [(id: UUID, name: String)] = []
    ) -> LibraryItem {
        var record = GenerationRecord(
            GeneratedImage(
                pngData: Data(),
                settings: GenerationSettings(
                    prompt: prompt, size: ImageSize(width: 1024, height: 1024), steps: 9,
                    guidance: 3, seed: seed),
                modelID: modelID,
                createdAt: created,
                duration: .seconds(3)
            )
        )
        record.modelID = modelID
        return LibraryItem(
            url: URL(filePath: "/Zephra/\(prompt)-\(seed).png"),
            collection: collection,
            provenance: .generated(record),
            annotation: LibraryAnnotation(
                isFavourite: favourite,
                tags: tags,
                albums: albums.map { LibraryAnnotation.Membership(id: $0.id, name: $0.name) }
            ),
            fileSize: 1024,
            contentModifiedAt: created,
            calendar: calendar
        )
    }

    private static func query(text: String) -> LibraryQuery {
        LibraryQuery(text: text)
    }
}
