import Testing
import ZephraCore

@testable import Zephra

@Suite("What a reference picture means to the model reading it")
struct ReferenceRoleTests {
    @Test("LTX-2.5 holds the picture as the clip's first frame")
    func ltx2IsFirstFrame() {
        let role = ReferenceRole(capabilities: ModelCatalog.ltx2Distilled4bit.capabilities)
        #expect(role == .firstFrame)
        #expect(role.wellCaption == "First frame")
        #expect(role.inspectorRowLabel == "First frame")
    }

    @Test("Z-Image starts from a noised copy of the picture")
    func zImageIsStartFrom() {
        let role = ReferenceRole(capabilities: ModelCatalog.zImageTurbo4bit.capabilities)
        #expect(role == .startFrom)
        #expect(role.wellCaption == "Start from")
        #expect(role.inspectorRowLabel == "Started from")
    }

    @Test("FLUX.2 klein reads the picture as tokens rather than starting from it")
    func kleinIsReference() {
        let role = ReferenceRole(capabilities: ModelCatalog.flux2Klein4bit.capabilities)
        #expect(role == .reference)
        #expect(role.wellCaption == "Reference")
        #expect(role.inspectorRowLabel == "Edited from")
    }

    @Test("a model that both makes clips and adjusts strength still reads as the clip role")
    func producesVideoWinsOverAdjustsStrength() {
        let capabilities = ModelCatalog.ltx2Distilled4bit.capabilities
        #expect(capabilities.producesVideo)
        #expect(capabilities.adjustsReferenceStrength, "LTX-2.5's bounds are not degenerate either")
        #expect(ReferenceRole(capabilities: capabilities) == .firstFrame)
    }

    @Test("every string is distinct per role, so nothing accidentally shares another's wording")
    func stringsDontCollideAcrossRoles() {
        let roles: [ReferenceRole] = [.firstFrame, .continues, .startFrom, .reference]
        #expect(Set(roles.map(\.wellCaption)).count == 4)
        #expect(Set(roles.map(\.emptyWellHelp)).count == 4)
        #expect(Set(roles.map(\.filledWellAccessibilityLabel)).count == 4)
        #expect(Set(roles.map(\.openPanelMessage)).count == 4)
        #expect(Set(roles.map(\.strengthHelp)).count == 4)
        #expect(Set(roles.map(\.inspectorRowLabel)).count == 4)
    }

    @Test("while the capsule carries a continuation, a clip model's picture is the clip's end")
    func continuingIsItsOwnRole() {
        let capabilities = ModelCatalog.ltx2Distilled4bit.capabilities
        #expect(ReferenceRole(capabilities: capabilities, continuing: true) == .continues)
        #expect(ReferenceRole(capabilities: capabilities, continuing: false) == .firstFrame)
        // A picture model never continues anything, whatever the capsule says.
        #expect(ReferenceRole(capabilities: ModelCatalog.zImageTurbo4bit.capabilities, continuing: true) == .startFrom)
        #expect(ReferenceRole.continues.wellCaption == "Continues from")
    }
}
