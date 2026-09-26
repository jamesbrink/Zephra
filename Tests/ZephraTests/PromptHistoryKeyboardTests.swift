import AppKit
import SwiftUI
import Testing
@testable import Zephra

@MainActor @Suite("Prompt history arrows preserve editing")
struct PromptHistoryKeyboardTests {
    @Test func multilineRecallAndDraftRestoration() {
        var text = "unsent\ndraft"
        let editor = PromptTextView(text: Binding(get: { text }, set: { text = $0 }),
            isFocused: .constant(true), history: ["newer\nmultiline prompt", "older"])
        let delegate = editor.makeCoordinator()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        view.delegate = delegate; view.string = text; view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(delegate.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(text == "newer\nmultiline prompt")
        #expect(delegate.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(text == "older")
        #expect(delegate.textView(view, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(text == "newer\nmultiline prompt")
        #expect(delegate.textView(view, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(text == "unsent\ndraft")
    }
    @Test func selectionAndMiddleLinesKeepNativeNavigation() {
        var text = "first\nsecond\nthird"
        let editor = PromptTextView(text: Binding(get: { text }, set: { text = $0 }),
            isFocused: .constant(true), history: ["saved"])
        let delegate = editor.makeCoordinator()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        view.string = text
        view.setSelectedRange(NSRange(location: 0, length: 2))
        #expect(!delegate.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        view.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(!delegate.textView(view, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(text == "first\nsecond\nthird")
    }
}
