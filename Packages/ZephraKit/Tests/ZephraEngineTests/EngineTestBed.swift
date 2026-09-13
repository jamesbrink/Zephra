import Foundation
import ZephraCore

@testable import ZephraEngine

/// One test's throwaway output folder and its backend dial, so each test starts from nothing.
///
/// The folder is never created here: `ImageLibrary` makes it on the first write, which is what
/// lets a test tell "no image was saved" apart from "an empty folder was left behind".
@MainActor
final class EngineTestBed {
    /// The backend's behaviour, shared with every mock the factory produces.
    let control = MockBackendControl()
    /// A reading that follows the bed's dial rather than being fixed when a store is made, so
    /// a test can starve the Mac, watch the load refused, and hand the memory back for a retry.
    struct DialMachineMemory: MachineMemoryReader {
        let control: MockBackendControl
        func read() -> MachineMemory? { control.settings.machine }
    }
    /// The upscaler's behaviour, shared the same way.
    let upscalerControl = MockUpscalerControl()
    /// The clip reader and joiner every store this bed makes is given.
    let clips = MockClipEditing()
    /// What the Mac is said to have free, which every store this bed makes reads live through
    /// `DialMachineMemory`. Roomy by default and settable at any point, so a suite about the
    /// memory guard can starve the machine, watch a load refused and hand the memory back for
    /// the retry, and no other suite's result depends on what the Mac running it is doing.
    var machineMemory: MachineMemory? {
        get { control.settings.machine }
        set { control.update { $0.machine = newValue } }
    }
    /// What the GPU is said to be allowed to keep. Roomy for the same reason: every catalog
    /// model fits, so a load in a suite about something else is never refused by the guard.
    var memoryBudget = MemoryBudget(
        physicalMemory: 128_000_000_000, gpuWorkingSet: 100_000_000_000)
    /// Where generated images are written.
    let directory = URL(filePath: NSTemporaryDirectory())
        .appending(path: "ZephraEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() {
        machineMemory = MachineMemory(
            physicalBytes: 128_000_000_000, availableBytes: 120_000_000_000)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The output folder seen as a library, for filling it the way an earlier session would
    /// have before a store is made over it.
    var library: ImageLibrary { ImageLibrary(root: directory) }

    /// Every family the catalog names, which is what a store the app builds would be given.
    ///
    /// Derived rather than listed: a test about queueing or history should not start failing
    /// the day a model from a new family is added, and one that cares about a missing engine
    /// says so by passing its own list.
    static let catalogFamilies: [BackendID] = {
        var seen: [BackendID] = []
        for descriptor in ModelCatalog.all where !seen.contains(descriptor.backend) {
            seen.append(descriptor.backend)
        }
        return seen
    }()

    /// A registry in which the mock backend answers for every family this bed's tests use.
    func registry(_ families: [BackendID] = catalogFamilies) -> BackendRegistry {
        let control = control
        var registry = BackendRegistry()
        for family in families {
            registry.register(family) { _ in MockBackend(control: control) }
        }
        return registry
    }

    /// A store wired to the mock backend, the mock upscaler, and this bed's output folder.
    func store(
        descriptor: ModelDescriptor = ModelCatalog.default,
        locations: ModelLocations? = nil
    ) -> GenerationStore {
        store(descriptor: descriptor, locations: locations, upscaler: upscalerFactory())
    }

    /// A store with no upscaler in it, which is what a build carrying none looks like.
    func storeWithoutUpscaler(
        descriptor: ModelDescriptor = ModelCatalog.default
    ) -> GenerationStore {
        store(descriptor: descriptor, upscaler: nil)
    }

    /// A store wired to whichever upscaler is asked for.
    ///
    /// `output` is the folder written to, which is this bed's own unless a test wants writes
    /// that cannot land; every store comes through here, so no store reads the real Mac's
    /// memory and a suite's result never depends on what the machine running it is doing.
    func store(
        descriptor: ModelDescriptor = ModelCatalog.default,
        locations: ModelLocations? = nil,
        upscaler: UpscalerFactory?,
        output: URL? = nil,
        families: [BackendID] = catalogFamilies
    ) -> GenerationStore {
        let store = GenerationStore(
            descriptor: descriptor,
            registry: registry(families),
            outputDirectory: output ?? directory,
            locations: locations ?? ModelLocations(root: directory.appending(path: "models")),
            upscaler: upscaler,
            runtime: MockInferenceRuntime(control: control),
            clips: clips,
            machineMemory: DialMachineMemory(control: control)
        )
        store.memoryBudget = memoryBudget
        // The two policies follow the same roomy budget, so what a suite about queueing or
        // history gets is the same on every Mac rather than whatever the one running it has.
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .automatic, budget: memoryBudget)
        store.vaeTilingPolicy = VAETilingPolicy(mode: .automatic, budget: memoryBudget)
        return store
    }

    /// A factory making mock upscalers that all read this bed's one dial.
    func upscalerFactory() -> UpscalerFactory {
        let control = upscalerControl
        return { MockUpscaler(control: control) }
    }

    /// A store whose writes can never succeed: the output folder would have to be created
    /// inside a plain file, which the file system refuses, so every save fails.
    func storeThatCannotSave() throws -> GenerationStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "not-a-folder")
        try Data().write(to: blocker)
        return store(
            upscaler: upscalerFactory(),
            output: blocker.appending(path: "images", directoryHint: .isDirectory)
        )
    }

    /// An index over this bed's folder. `settleFor` is the folder watch's debounce, which a
    /// test wants in milliseconds rather than the app's quarter of a second.
    func index(settleFor: Duration = .milliseconds(20)) -> LibraryIndex {
        LibraryIndex(library: library, settleFor: settleFor)
    }

    /// The file names written so far, newest-first order not guaranteed.
    func writtenFiles() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        return try FileManager.default
            .contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
    }

    /// How many denoising steps the mock has reported so far, for a test that has to wait for
    /// a *second* generation and so cannot wait for the count to leave zero.
    var stepsEmitted: Int { control.settings.stepsEmitted }

    /// Blocks until the mock has reported a denoising step past `baseline`, so a cancel lands
    /// mid-run rather than before the generation has begun.
    ///
    /// `baseline` matters whenever a test starts a second run: the tally is cumulative, so
    /// waiting for it to exceed zero returns instantly and the cancel lands on nothing.
    func waitForStep(beyond baseline: Int = 0) async throws {
        for _ in 0..<500 {
            if control.settings.stepsEmitted > baseline { return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Blocks until the mock upscaler has reported a tile, so a stop lands mid-run rather than
    /// before the first tile has been through.
    func waitForTile(beyond baseline: Int = 0) async throws {
        for _ in 0..<500 {
            if upscalerControl.settings.tilesEmitted > baseline { return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Blocks until `store` reaches `state`, so a cancel lands on work in progress rather than
    /// before it has begun. Gives up after a second, leaving the test to fail on its own terms.
    func waitFor(_ store: GenerationStore, toReach state: EngineState) async throws {
        for _ in 0..<500 {
            if store.state == state { return }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
