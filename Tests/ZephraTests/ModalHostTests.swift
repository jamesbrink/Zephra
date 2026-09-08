import AppKit
import Foundation
import Testing

@testable import Zephra

/// What the keyboard does to the app's questions. An `NSAlert` that is built but never run needs
/// no window and no run loop, so the whole of this reads the buttons of the real alerts the app
/// puts up rather than a description of them.
///
/// The rule these pin is AppKit's, and it is the opposite of what it looks like:
/// `addButton(withTitle:)` gives the *first* button Return, `hasDestructiveAction` only tints,
/// and a button titled "Cancel" takes Escape whatever its position — added first, "Cancel" takes
/// Escape and leaves the alert with no Return button at all.
@Suite("What Return and Escape do to the app's alerts")
struct ModalHostTests {
    private let source = URL(filePath: "/library", directoryHint: .isDirectory)
    private let destination = URL(filePath: "/elsewhere", directoryHint: .isDirectory)

    private func keys(_ alert: NSAlert) -> [String: String] {
        Dictionary(uniqueKeysWithValues: alert.buttons.map { ($0.title, $0.keyEquivalent) })
    }

    @Test("the first button added is the one Return presses")
    func firstButtonTakesReturn() {
        let alert = ModalHost.warning("m", "i", buttons: ["Keep Both", "Replace", "Cancel"])
        #expect(alert.buttons.map(\.title) == ["Keep Both", "Replace", "Cancel"])
        #expect(keys(alert)["Keep Both"] == "\r")
        #expect(keys(alert)["Replace"] == "")
    }

    @Test("a button titled Cancel is the one Escape presses, wherever it sits")
    func cancelTakesEscape() {
        #expect(keys(ModalHost.warning("m", "i", buttons: ["A", "Cancel"]))["Cancel"] == "\u{1b}")
        #expect(keys(ModalHost.warning("m", "i", buttons: ["A", "B", "Cancel"]))["Cancel"] == "\u{1b}")
    }

    @Test("a destructive answer is tinted and is never what Return gives")
    func destructiveIsNeverTheDefault() {
        let alert = ModalHost.warning("m", "i", buttons: ["Erase", "Cancel"], destructive: "Erase")
        #expect(alert.buttons.first?.hasDestructiveAction == true)
        #expect(keys(alert)["Erase"] == "")
        #expect(keys(alert)["Cancel"] == "\u{1b}")
        // No button holds Return: Escape cancels, and no single keystroke erases.
        #expect(!alert.buttons.contains { $0.keyEquivalent == "\r" })
    }

    @Test("a guarded answer loses Return without being drawn in red")
    func guardedIsNeitherDefaultNorTinted() {
        let alert = ModalHost.warning("m", "i", buttons: ["Move", "Cancel"], guarded: "Move")
        #expect(alert.buttons.allSatisfy { !$0.hasDestructiveAction })
        #expect(keys(alert)["Move"] == "")
    }

    @Test("deleting images for good puts no keystroke on Delete")
    func purgeHasNoDefault() {
        let alert = PurgeConfirmation.alert(count: 3)
        #expect(alert.messageText == "Delete these 3 images?")
        #expect(alert.buttons.first?.title == "Delete")
        #expect(alert.buttons.first?.hasDestructiveAction == true)
        #expect(keys(alert)["Delete"] == "")
        #expect(keys(alert)["Cancel"] == "\u{1b}")
    }

    @Test("changing the images folder defaults to keeping the images in place")
    func imagesFolderDefaultsToKeeping() {
        let alert = ImageDirectoryChoice.alert(moving: source, to: destination)
        #expect(alert.buttons.map(\.title) == ["Keep in Place", "Move Images", "Cancel"])
        #expect(keys(alert)["Keep in Place"] == "\r")
        #expect(keys(alert)["Move Images"] == "")
    }

    @Test("changing the models folder defaults to keeping the models in place")
    func modelsFolderDefaultsToKeeping() {
        let alert = ModelDirectoryChoice.alert(moving: source, to: destination)
        #expect(alert.buttons.map(\.title) == ["Keep in Place", "Move Models", "Cancel"])
        #expect(keys(alert)["Keep in Place"] == "\r")
        #expect(keys(alert)["Move Models"] == "")
    }

    @Test("moving models into the current folder puts no keystroke on the move")
    func moveModelsHereHasNoDefault() {
        let alert = ModelDirectoryChoice.moveAlert(from: source, to: destination)
        #expect(alert.buttons.map(\.title) == ["Move Models", "Cancel"])
        #expect(keys(alert)["Move Models"] == "")
        #expect(keys(alert)["Cancel"] == "\u{1b}")
    }

    @Test("an export collision defaults to keeping both files")
    func collisionDefaultsToKeepBoth() {
        let files = [source.appending(path: "a.png")]
        let plan = ExportPlan.make(
            files: files, into: destination, exists: { _ in true }, isSameFile: { _, _ in false })
        let alert = ExportCollisionPrompt.alert(about: plan, in: destination)
        #expect(alert.buttons.map(\.title) == ["Keep Both", "Replace", "Cancel"])
        #expect(keys(alert)["Keep Both"] == "\r")
    }
}
