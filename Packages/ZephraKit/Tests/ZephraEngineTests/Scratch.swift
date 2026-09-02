import Foundation
import ZephraCore

@testable import ZephraEngine

/// One test's throwaway output folder and its backend dial, so each test starts from nothing.
///
/// The folder is never created here: `ImageLibrary` makes it on the first write, which is what
/// lets a test tell "no image was saved" apart from "an empty folder was left behind".
@MainActor
final class Scratch {
    /// The backend's behaviour, shared with every mock the factory produces.
    let control = MockBackendControl()
    /// Where generated images are written.
    let directory = URL(filePath: NSTemporaryDirectory())
        .appending(path: "ZephraEngineTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A store wired to the mock backend and to this scratch folder.
    func store() -> GenerationStore {
        let control = control
        return GenerationStore(
            backendFactory: { _ in MockBackend(control: control) },
            outputDirectory: directory
        )
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
}
