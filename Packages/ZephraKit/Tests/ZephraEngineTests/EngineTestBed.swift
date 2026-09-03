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
    /// Where generated images are written.
    let directory = URL(filePath: NSTemporaryDirectory())
        .appending(path: "ZephraEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)

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

    /// A store wired to the mock backend and to this bed's output folder.
    func store(descriptor: ModelDescriptor = ModelCatalog.default) -> GenerationStore {
        GenerationStore(
            descriptor: descriptor,
            registry: registry(),
            outputDirectory: directory
        )
    }

    /// A store whose writes can never succeed: the output folder would have to be created
    /// inside a plain file, which the file system refuses, so every save fails.
    func storeThatCannotSave() throws -> GenerationStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "not-a-folder")
        try Data().write(to: blocker)
        return GenerationStore(
            registry: registry(),
            outputDirectory: blocker.appending(path: "images", directoryHint: .isDirectory)
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

    /// Blocks until the mock has reported one denoising step, so a cancel lands mid-run rather
    /// than before the generation has begun.
    func waitForFirstStep() async throws {
        for _ in 0..<500 {
            if control.settings.stepsEmitted > 0 { return }
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
