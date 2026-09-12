import Foundation
import Testing

@testable import Zephra

@Suite("Which copies of Zephra may replace themselves")
struct UpdateEligibilityTests {
    private let home = URL(filePath: "/Users/someone")
    private let stamp = "202609120231"

    private func verdict(
        build: String? = nil, path: String, overridden: Bool = false
    ) -> UpdateEligibility {
        UpdateEligibility.of(
            build: build ?? stamp, bundle: URL(filePath: path), home: home, overridden: overridden)
    }

    @Test("a stamped build in either Applications folder may, a folder of its own included")
    func applicationsIsEligible() {
        #expect(verdict(path: "/Applications/Zephra.app") == .eligible)
        #expect(verdict(path: "/Users/someone/Applications/Zephra.app") == .eligible)
        #expect(verdict(path: "/Applications/Graphics/Zephra.app") == .eligible)
        #expect(verdict(path: "/Applications/Zephra.app").refusal == nil)
    }

    @Test("a copy running from its disk image is told to move itself first")
    func translocatedIsRefused() {
        let translocated = "/private/var/folders/x9/abc/AppTranslocation/AABBCC/d/Zephra.app"
        #expect(verdict(path: translocated) == .translocated)
        #expect(verdict(path: translocated).refusal?.contains("Applications") == true)
    }

    @Test("translocation is answered before anything else, since the path says nothing else")
    func translocationComesFirst() {
        let translocated = "/private/var/folders/x9/abc/AppTranslocation/AABBCC/d/Zephra.app"
        #expect(verdict(build: "1", path: translocated, overridden: true) == .translocated)
    }

    @Test("a build number that is not a twelve-digit stamp is a development build")
    func developmentBuildIsRefused() {
        #expect(verdict(build: "1", path: "/Applications/Zephra.app") == .developmentBuild)
        #expect(verdict(build: "", path: "/Applications/Zephra.app") == .developmentBuild)
        // Even the Debug hand run has to be given a stamp before it is offered anything.
        #expect(verdict(build: "1", path: "/tmp/build/Debug/Zephra.app", overridden: true) == .developmentBuild)
    }

    @Test("a stamped copy anywhere else is refused, unless a Debug feed override is driving it")
    func elsewhereIsRefusedUnlessOverridden() {
        #expect(verdict(path: "/Users/someone/Downloads/Zephra.app") == .notInApplications)
        #expect(verdict(path: "/Applications/Other.app/Contents/Zephra.app") == .notInApplications)
        #expect(verdict(path: "/Users/someone/Downloads/Zephra.app", overridden: true) == .eligible)
        #expect(verdict(path: "/Users/someone/Downloads/Zephra.app").refusal != nil)
    }

    @Test("only an eligible copy says it can install")
    func onlyEligibleInstalls() {
        #expect(UpdateEligibility.eligible.canInstall)
        for refused in [UpdateEligibility.translocated, .developmentBuild, .notInApplications] {
            #expect(!refused.canInstall)
            #expect(refused.refusal?.isEmpty == false)
        }
    }
}
