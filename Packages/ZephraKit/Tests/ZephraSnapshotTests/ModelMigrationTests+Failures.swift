import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraSnapshot

extension ModelMigrationTests {
    @Test("insufficient capacity refuses before copying or removing a model")
    func insufficientSpace() throws {
        let scratch = Scratch("SpaceMigration")
        let path = "Downloads/mzbac--Z-Image-Turbo-8bit/weights"
        try scratch.write("source", to: "old/\(path)")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        #expect(throws: ModelDirectoryError.self) {
            try move.run(progress: { _ in }, publish: FileManager.default.moveItem,
                         removeSource: FileManager.default.removeItem, availableBytes: 0)
        }
        #expect(scratch.hasFile("old/\(path)"))
        #expect(!scratch.hasFile("new/\(path)"))
    }

    @Test("cancellation before publication retains originals")
    func cancellationPreservesSource() async throws {
        let scratch = Scratch("CancelledMigration")
        let path = "Downloads/mzbac--Z-Image-Turbo-8bit/weights"
        try scratch.write("source", to: "old/\(path)")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try move.run()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(scratch.hasFile("old/\(path)"))
        #expect(!scratch.hasFile("new/\(path)"))
    }

    @Test("failure after one publication retains all sources and reports the verified duplicate")
    func laterPublicationFailure() throws {
        let scratch = Scratch("LaterPublishFailure")
        let download = "Downloads/mzbac--Z-Image-Turbo-8bit/weights"
        let built = "z-image-turbo-4bit/weights"
        try scratch.write("release", to: "old/\(download)")
        try scratch.write("built", to: "old/\(built)")
        let move = ModelMigration(from: scratch.url("old"), to: scratch.url("new"))
        var count = 0
        #expect(throws: ModelDirectoryError.self) {
            try move.run(progress: { _ in }, publish: { source, target in
                count += 1
                if count == 2 { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.moveItem(at: source, to: target)
            }, removeSource: { _ in Issue.record("Sources must remain until every publication succeeds") })
        }
        #expect(scratch.hasFile("old/\(download)"))
        #expect(scratch.hasFile("old/\(built)"))
        #expect(scratch.hasFile("new/\(download)"))
    }
}
