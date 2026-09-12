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

    @Test("only our own team's signature is accepted, and an unreadable one fails closed")
    func theTeamMustBeOurs() {
        #expect(UpdateSignature.matches(theirs: AppFacts.teamIdentifier))
        // Notarized, so `spctl` passes it, and signed by somebody else.
        #expect(!UpdateSignature.matches(theirs: "SOMEBODYELSE"))
        // Unsigned, or a signature the Security framework would not read: refused, rather
        // than treated as "nothing to compare against".
        #expect(!UpdateSignature.matches(theirs: nil))
    }

    @Test("a Debug feed override may take an unsigned candidate, and still not another team's")
    func theOverrideTakesAnAdHocCandidateOnly() {
        #expect(UpdateSignature.matches(theirs: nil, overridden: true))
        #expect(!UpdateSignature.matches(theirs: "SOMEBODYELSE", overridden: true))
        #expect(UpdateSignature.matches(theirs: AppFacts.teamIdentifier, overridden: true))
    }

    @Test("the team is a constant, not whatever this process says about itself")
    func theTeamIsWrittenDown() {
        #expect(AppFacts.teamIdentifier == "28X9H69QGE")
    }

    @Test("only the folder failure offers the disk image to install by hand")
    func onlyTheFolderFailureOffersTheImage() {
        #expect(UpdateInstallError.cannotReplaceItself(folder: "/Applications").offersTheDiskImage)
        #expect(!UpdateInstallError.differentSigner.offersTheDiskImage)
        #expect(!UpdateInstallError.notAZephra.offersTheDiskImage)
        #expect(UpdateInstallError.notAZephra.message.isEmpty == false)
    }

    @Test("a rollback that did not land says where the app actually is")
    func aFailedRollbackNamesTheAside() {
        let said = UpdateInstallError.rollbackFailed(aside: "/Applications/Zephra.previous.app").message
        #expect(said.contains("/Applications/Zephra.previous.app"))
        #expect(said.contains("Zephra.app"))
    }
}
