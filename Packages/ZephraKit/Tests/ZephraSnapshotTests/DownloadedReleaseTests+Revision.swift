import Foundation
import Testing
import ZephraCore
import ZephraSnapshot
import ZephraTestSupport

extension DownloadedReleaseTests {
    @Test("completed releases and packed variants do not satisfy another explicit revision")
    func completedRevisionIdentity() throws {
        let scratch = Scratch("CompletedRevision")
        let locations = ModelLocations(root: scratch.url("models"))
        let folder = "models/Downloads/org--repo"
        try Self.snapshot(scratch, at: folder)
        try scratch.write("v1", to: "\(folder)/.zephra-requested-revision")
        try scratch.write("sha1", to: "\(folder)/.zephra-commit")
        #expect(check.downloadedRelease(of: Self.model(revision: "v1"), in: locations) != nil)
        #expect(check.downloadedRelease(of: Self.model(revision: "sha1"), in: locations) != nil)
        #expect(check.downloadedRelease(of: Self.model(revision: "v2"), in: locations) == nil)
        #expect(check.downloadedRelease(of: Self.model(), in: locations) == nil)
        let model = Self.model(revision: "v1")
        try Self.snapshot(scratch, at: "models/\(model.id)")
        #expect(check.packedVariant(of: model, in: locations) == nil)
        try PackedProvenance.write(model, into: locations.built(model))
        #expect(check.packedVariant(of: model, in: locations) != nil)
        #expect(check.packedVariant(of: Self.model(revision: "v2"), in: locations) == nil)
    }
}
