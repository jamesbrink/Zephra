import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("Expanding one press of Generate into a batch")
struct BatchExpansionTests {
    private func settings(seed: UInt64) -> GenerationSettings {
        GenerationSettings(
            prompt: "a red bicycle against a limestone wall",
            size: ImageSize(width: 1024, height: 1024),
            steps: 4,
            guidance: 0,
            seed: seed
        )
    }

    @Test("the first image keeps the seed in the field and only the rest are fresh")
    func firstKeepsItsSeed() {
        var next: UInt64 = 100
        let expanded = BatchExpansion.expand(settings(seed: 7), count: 4) {
            defer { next += 1 }
            return next
        }
        #expect(expanded.map(\.seed) == [7, 100, 101, 102])
    }

    @Test("a batch of one is exactly the settings it was handed, and asks for no seed")
    func oneIsUntouched() {
        var asked = 0
        let expanded = BatchExpansion.expand(settings(seed: 7), count: 1) {
            asked += 1
            return 0
        }
        #expect(expanded == [settings(seed: 7)])
        #expect(asked == 0)
    }

    @Test("everything but the seed carries across every copy")
    func onlyTheSeedVaries() {
        let expanded = BatchExpansion.expand(settings(seed: 7), count: 3) { .random(in: .min ... .max) }
        #expect(expanded.count == 3)
        #expect(Set(expanded.map(\.prompt)).count == 1)
        #expect(Set(expanded.map(\.steps)) == [4])
        #expect(Set(expanded.map(\.size)).count == 1)
    }

    @Test("a count of nothing expands to nothing")
    func nothingExpandsToNothing() {
        #expect(BatchExpansion.expand(settings(seed: 7), count: 0) { 0 }.isEmpty)
    }
}
