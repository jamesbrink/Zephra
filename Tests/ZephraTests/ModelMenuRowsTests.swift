import Testing
import ZephraCore

@testable import Zephra

/// What the toolbar's model pull-down lists, and what each row says.
@Suite("the model menu")
struct ModelMenuRowsTests {
    /// A Mac with room for everything in the catalog, so a test about the disk is not quietly
    /// a test about memory.
    private let budget = MemoryBudget(physicalMemory: 192 << 30)
    private let chosen = ModelCatalog.zImageTurbo8bit
    private let other = ModelCatalog.zImageTurbo4bit

    private func rows(
        availability: [ModelDescriptor.ID: ModelAvailability] = [:],
        downloading: Set<ModelDescriptor.ID> = [],
        chosen: ModelDescriptor? = nil,
        loaded: ModelDescriptor? = nil,
        residency: WeightResidency? = nil,
        budget: MemoryBudget? = nil
    ) -> [ModelMenuRows.Row] {
        ModelMenuRows.rows(
            budget: budget ?? self.budget, availability: availability, downloading: downloading,
            chosen: chosen ?? self.chosen, loaded: loaded, residency: residency)
    }

    @Test("lists only the models that are on this Mac")
    func listsWhatIsOnDisk() {
        let listed = rows(availability: [other.id: .available])
        #expect(Set(listed.map(\.id)) == [chosen.id, other.id])
        #expect(listed.count < ModelCatalog.all.count)
    }

    @Test("keeps the chosen model on the list when it has not been downloaded")
    func keepsTheChosenModel() {
        let listed = rows(availability: [chosen.id: .needsDownload(bytes: 13_280_000_000)])
        let row = listed.first { $0.id == chosen.id }
        #expect(row?.isChosen == true)
        #expect(row?.note == "13.3 GB download")
        #expect(row?.isEnabled == true)
    }

    @Test("lists a model whose download is in flight, and says so")
    func listsALiveDownload() {
        let listed = rows(
            availability: [other.id: .needsDownload(bytes: 13_280_000_000)],
            downloading: [other.id])
        #expect(listed.first { $0.id == other.id }?.note == "Downloading\u{2026}")
    }

    @Test("says Loaded on the loaded model, and Streaming when its weights come off the disk")
    func marksTheLoadedModel() {
        let resident = rows(
            availability: [other.id: .available], loaded: chosen, residency: .resident)
        #expect(resident.first { $0.id == chosen.id }?.note == "Loaded")
        let streamed = rows(
            availability: [other.id: .available], loaded: chosen, residency: .streamed)
        #expect(streamed.first { $0.id == chosen.id }?.note == "Streaming")
    }

    @Test("greys a model this Mac cannot hold, and says what it needs")
    func greysWhatCannotBeHeld() throws {
        let tight = try #require(ModelCatalog.all.max { $0.leanestPeakBytes < $1.leanestPeakBytes })
        let small = MemoryBudget(physicalMemory: 8 << 30)
        try #require(!ModelCatalog.fit(tight, budget: small).isSelectable)
        let row = try #require(
            rows(availability: [tight.id: .available], chosen: tight, budget: small)
                .first { $0.id == tight.id })
        #expect(!row.isEnabled)
        #expect(row.note?.hasPrefix("Needs ") == true)
        #expect(row.help.contains("cannot be chosen here"))
    }

    @Test("lists the models this Mac runs before the ones it cannot")
    func ordersRunnableFirst() throws {
        let small = MemoryBudget(physicalMemory: 16 << 30)
        let everything = Dictionary(
            uniqueKeysWithValues: ModelCatalog.all.map { ($0.id, ModelAvailability.available) })
        let listed = rows(availability: everything, budget: small)
        #expect(listed.count == ModelCatalog.all.count)
        let enabled = listed.map(\.isEnabled)
        #expect(enabled == enabled.sorted { $0 && !$1 })
    }

    @Test("says nothing beside a model that is simply here and not loaded")
    func saysNothingWhenThereIsNothingToSay() {
        #expect(rows(availability: [other.id: .available]).first { $0.id == other.id }?.note == nil)
    }
}
