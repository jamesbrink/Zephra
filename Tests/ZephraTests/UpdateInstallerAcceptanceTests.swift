import Foundation
import Testing
import ZephraSnapshot

@testable import Zephra

@Suite("Whether a downloaded app is the release the manifest promised")
struct UpdateInstallerAcceptanceTests {
    private let manifest = ReleaseManifest(
        url: URL(string: "https://example.test/releases/Zephra-0.1.0-202609120231.dmg")!,
        version: "0.1.0", build: "202609120231", sha256: String(repeating: "a", count: 64))
    private let ours = "io.zephra.Zephra"

    private func refusal(_ info: [String: String]) -> String? {
        UpdateInstaller.acceptance(info: info, manifest: manifest, ourIdentifier: ours)
    }

    @Test("the identifier and the build the manifest named are accepted")
    func theRightAppIsAccepted() {
        #expect(refusal(["CFBundleIdentifier": ours, "CFBundleVersion": "202609120231"]) == nil)
    }

    @Test("another app wearing our name is not Zephra")
    func anotherIdentifierIsRefused() {
        #expect(refusal(["CFBundleIdentifier": "com.example.Other", "CFBundleVersion": "202609120231"]) != nil)
        #expect(refusal(["CFBundleVersion": "202609120231"]) != nil)
        #expect(refusal([:]) != nil)
    }

    @Test("a build other than the published one is refused, and the sentence names both")
    func anotherBuildIsRefused() {
        let said = refusal(["CFBundleIdentifier": ours, "CFBundleVersion": "202609112359"])
        #expect(said?.contains("202609112359") == true)
        #expect(said?.contains("202609120231") == true)
        #expect(refusal(["CFBundleIdentifier": ours]) != nil)
    }

    @Test("the version is deliberately not compared, since every build is 0.1.0")
    func theVersionIsNotTheTest() {
        #expect(refusal([
            "CFBundleIdentifier": ours, "CFBundleVersion": "202609120231",
            "CFBundleShortVersionString": "9.9.9",
        ]) == nil)
    }

    @Test("an ad-hoc copy of our own has no team to compare, so the signer check is skipped")
    func adHocSkipsTheTeamCheck() {
        #expect(UpdateSignature.matches(ours: nil, theirs: nil))
        #expect(UpdateSignature.matches(ours: nil, theirs: "28X9H69QGE"))
        #expect(UpdateSignature.matches(ours: "28X9H69QGE", theirs: "28X9H69QGE"))
        #expect(!UpdateSignature.matches(ours: "28X9H69QGE", theirs: "SOMEBODYELSE"))
        #expect(!UpdateSignature.matches(ours: "28X9H69QGE", theirs: nil))
    }

    @Test("only the folder failure offers the disk image to install by hand")
    func onlyTheFolderFailureOffersTheImage() {
        #expect(UpdateInstallError.cannotReplaceItself(folder: "/Applications").offersTheDiskImage)
        #expect(!UpdateInstallError.differentSigner.offersTheDiskImage)
        #expect(!UpdateInstallError.notAZephra.offersTheDiskImage)
        #expect(UpdateInstallError.notAZephra.message.isEmpty == false)
    }
}
