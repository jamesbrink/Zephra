import Foundation
import Testing

@testable import Zephra

@Suite("What an export into a folder would do")
struct ExportPlanTests {
    private let folder = URL(filePath: "/exports", directoryHint: .isDirectory)
    private let library = URL(filePath: "/library", directoryHint: .isDirectory)

    private func file(_ name: String, in folder: URL) -> URL { folder.appending(path: name) }

    @Test("a folder with no conflicts yields only copies, each under its own name")
    func noConflictsYieldsOnlyCopies() {
        let files = [file("a.png", in: library), file("b.png", in: library)]
        let plan = ExportPlan.make(files: files, into: folder, exists: { _ in false }, isSameFile: { _, _ in false })
        #expect(plan.copies.map(\.destination) == [file("a.png", in: folder), file("b.png", in: folder)])
        #expect(plan.copies.map(\.source) == files)
        #expect(plan.collisions.isEmpty)
        #expect(plan.alreadyThere.isEmpty)
    }

    @Test("a destination that is the source itself is already there, not a collision")
    func destinationThatIsTheSourceIsAlreadyThere() {
        let source = file("a.png", in: library)
        let plan = ExportPlan.make(
            files: [source], into: library, exists: { _ in true }, isSameFile: { $0 == $1 })
        #expect(plan.alreadyThere == [source])
        #expect(plan.copies.isEmpty)
        #expect(plan.collisions.isEmpty)
    }

    @Test("an existing other file is a collision")
    func existingOtherFileIsACollision() {
        let source = file("a.png", in: library)
        let plan = ExportPlan.make(
            files: [source], into: folder, exists: { _ in true }, isSameFile: { _, _ in false })
        #expect(plan.collisions == [ExportPlan.Copy(source: source, destination: file("a.png", in: folder))])
        #expect(plan.copies.isEmpty)
    }

    @Test("two sources with one name collide with each other even in an empty folder")
    func sameNameTwiceCollidesWithinTheBatch() {
        let first = file("a.png", in: library)
        let second = file("a.png", in: library.appending(path: "Sources"))
        let plan = ExportPlan.make(
            files: [first, second], into: folder, exists: { _ in false }, isSameFile: { _, _ in false })
        #expect(plan.copies.map(\.source) == [first])
        #expect(plan.collisions.map(\.source) == [second])
    }

    @Test("keep both picks \"name 2\", then \"name 3\", skipping names taken or on the disk")
    func keepBothNumbersPastTakenNames() {
        let destination = file("a.png", in: folder)
        let free = ExportPlan.keepBothName(for: destination, taken: [], exists: { _ in false })
        #expect(free == file("a 2.png", in: folder))
        let taken = ExportPlan.keepBothName(for: destination, taken: ["a 2.png"], exists: { _ in false })
        #expect(taken == file("a 3.png", in: folder))
        let onDisk = ExportPlan.keepBothName(
            for: destination, taken: ["a 2.png"], exists: { $0.lastPathComponent == "a 3.png" })
        #expect(onDisk == file("a 4.png", in: folder))
    }

    @Test("keeping both renames every collision into a copy and leaves nothing colliding")
    func keepingBothRenamesEveryCollision() {
        let sources = [file("a.png", in: library), file("b.png", in: library), file("a.png", in: library.appending(path: "x"))]
        let plan = ExportPlan.make(
            files: sources, into: folder,
            exists: { $0.lastPathComponent == "a.png" }, isSameFile: { _, _ in false })
        let kept = plan.keepingBoth(exists: { $0.lastPathComponent == "a.png" })
        #expect(kept.collisions.isEmpty)
        #expect(kept.copies.map(\.destination.lastPathComponent) == ["b.png", "a 2.png", "a 3.png"])
    }

    @Test("replacing promotes every collision to a copy and leaves the same-file ones alone")
    func replacingPromotesEveryCollision() {
        let same = file("same.png", in: folder)
        let other = file("other.png", in: library)
        let plan = ExportPlan.make(
            files: [same, other], into: folder, exists: { _ in true }, isSameFile: { $0 == $1 })
        let replaced = plan.replacing()
        #expect(replaced.copies == [ExportPlan.Copy(source: other, destination: file("other.png", in: folder))])
        #expect(replaced.collisions.isEmpty)
        #expect(replaced.alreadyThere == [same])
    }

    @Test("the prompt's headline counts the collisions against the whole batch")
    func promptHeadlineCountsTheBatch() {
        let sources = [file("a.png", in: library), file("b.png", in: library), file("c.png", in: folder)]
        let plan = ExportPlan.make(
            files: sources, into: folder,
            exists: { $0.lastPathComponent != "b.png" }, isSameFile: { $0 == $1 })
        #expect(ExportCollisionPrompt.headline(for: plan, in: folder) == "1 of 3 images already exists in “exports”.")
        #expect(ExportCollisionPrompt.explanation(for: plan).hasSuffix("1 is already in this folder and is left alone."))
    }
}
