import Testing

@testable import ZephraMobile

@Suite("Where the phone is looking")
@MainActor
struct MobileSelectionTests {
    @Test("tapping the collapsed prompt opens the settings and asks for the keyboard")
    func tappingThePrompt() {
        let selection = MobileSelection(tab: .canvas, capsuleIsExpanded: false)
        selection.expandCapsule(focusingPrompt: true)
        #expect(selection.capsuleIsExpanded)
        #expect(selection.promptIsFocused)
    }

    @Test("opening the settings some other way leaves the keyboard down")
    func openingWithoutTyping() {
        let selection = MobileSelection(tab: .canvas, capsuleIsExpanded: false)
        selection.expandCapsule()
        #expect(selection.capsuleIsExpanded)
        #expect(!selection.promptIsFocused)
    }

    @Test("putting the settings away drops the keyboard with them")
    func puttingThemAway() {
        let selection = MobileSelection(tab: .canvas, capsuleIsExpanded: false)
        selection.expandCapsule(focusingPrompt: true)
        selection.collapseCapsule()
        #expect(!selection.capsuleIsExpanded)
        #expect(!selection.promptIsFocused)
    }

    @Test("a launch opens with the keyboard down, whatever surface it was told to open on")
    func aLaunchAsksForNoKeyboard() {
        for expanded in [true, false] {
            let selection = MobileSelection(tab: .canvas, capsuleIsExpanded: expanded)
            #expect(selection.capsuleIsExpanded == expanded)
            #expect(!selection.promptIsFocused)
        }
    }

    @Test("the frozen capsule state opens the settings and asks for no keyboard")
    func theFrozenCapsuleState() {
        let selection = MobileSelection(
            tab: .canvas, capsuleIsExpanded: MobilePreview.capsuleIsExpanded)
        #expect(!selection.promptIsFocused)
        #expect(selection.capsuleIsExpanded == (MobilePreview.state == .capsule))
    }
}
