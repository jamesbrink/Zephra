import Foundation
import ZephraSnapshot

extension UpdateInstaller {
    /// Step 2: everything asked of the app on the mounted image, before this copy is touched.
    ///
    /// The order runs cheapest and most specific first: is there an app there at all, is it
    /// intact, will macOS run it, is it ours, and is it the release the manifest named.
    nonisolated static func verify(
        _ candidate: URL, manifest: ReleaseManifest, identifier: String, overridden: Bool
    ) throws {
        let path = candidate.path(percentEncoded: false)
        // A link rather than a bundle: `codesign` and `spctl` would follow it and report on
        // whatever it points at, and `ditto` would then copy that instead. Refused before any
        // of them is asked.
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let attributes, (attributes[.type] as? FileAttributeType) != .typeSymbolicLink else {
            throw UpdateInstallError.notAZephra
        }
        let signature = try UpdateTool.run(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", path])
        guard signature.succeeded else {
            throw UpdateInstallError.signatureInvalid(reason: signature.lastLine)
        }
        // Gatekeeper's own answer, which honours the stapled notarization ticket and so needs
        // no network. It is necessary and not sufficient: it accepts any notarized Developer
        // ID app, which is why the team identifier is asked for next.
        let assessment = try UpdateTool.run("/usr/sbin/spctl", ["--assess", "--type", "execute", path])
        guard assessment.succeeded else {
            throw UpdateInstallError.gatekeeperRefused(reason: assessment.lastLine)
        }
        guard UpdateSignature.matches(theirs: UpdateSignature.team(at: candidate), overridden: overridden)
        else { throw UpdateInstallError.differentSigner }
        if let refusal = acceptance(
            info: information(of: candidate), manifest: manifest, ourIdentifier: identifier)
        {
            throw UpdateInstallError.wrongApp(reason: refusal)
        }
    }

    /// Whether the app's own `Info.plist` is the release the manifest promised, or the sentence
    /// saying why it is not. Pure, so every way a download can be the wrong app is a test.
    ///
    /// The build is checked and not the version, for the reason nothing compares versions here:
    /// every build is 0.1.0. An image serving a build other than the one the manifest named is
    /// a mirror that has drifted, a manifest read from a cache, or somebody's substitution, and
    /// all three are answered the same way.
    nonisolated static func acceptance(
        info: [String: String], manifest: ReleaseManifest, ourIdentifier: String
    ) -> String? {
        guard let identifier = info["CFBundleIdentifier"], identifier == ourIdentifier else {
            return "The download is not a copy of Zephra."
        }
        guard let build = info["CFBundleVersion"], build == manifest.build else {
            return """
                The download says it is build \(info["CFBundleVersion"] ?? "unknown"), \
                but the update was published as build \(manifest.build).
                """
        }
        return nil
    }

    /// The `Info.plist` keys the acceptance reads, as strings; anything missing simply is not
    /// there, and the acceptance refuses it.
    private nonisolated static func information(of bundle: URL) -> [String: String] {
        let plist = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let read = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let facts = read as? [String: Any]
        else { return [:] }
        return facts.compactMapValues { $0 as? String }
    }
}
