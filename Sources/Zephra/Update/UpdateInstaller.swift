import Foundation
import ZephraSnapshot
import os

/// Mounts a verified disk image, checks the Zephra inside it, and swaps it for this one.
///
/// In process, with no privileged helper: Zephra is unsandboxed and lives in a folder its own
/// user can write, so the whole install is a rename and a copy. The order is what makes it
/// safe, and each step is the way it is for a reason:
///
/// 1. **Mount read-only**, on a mount point of ours under `Updates/`, so nothing appears in the
///    Finder and nothing is opened.
/// 2. **Verify on the mounted image, before anything here is touched.** `codesign` says the
///    signature is intact, `spctl` is Gatekeeper's own verdict — which honours the stapled
///    ticket with no network — the team identifier says it is ours rather than merely somebody's,
///    and the `Info.plist` has to be the identifier and the build the manifest promised. A
///    download that fails any of these is discarded with this copy untouched.
/// 3. **Rename this bundle aside** rather than deleting it: a running bundle may be renamed,
///    since the executable is mapped by inode, and the rename is what makes the swap
///    reversible.
/// 4. **`ditto`**, which is what `create-dmg.sh` already trusts to carry extended attributes,
///    resource forks and symbolic links — a `copyItem` that quietly drops one of those leaves
///    an app that will not launch. Then `codesign --verify` on the copy, because a copy is a
///    new set of bytes.
/// 5. **Roll back** on any failure: remove the half-copy, move the original back, and say so.
///
/// No quarantine handling is needed and none is done: `LSFileQuarantineEnabled` is unset, the
/// files on a mounted image carry no quarantine attribute of their own, and `spctl` has already
/// run Gatekeeper's assessment over the very bytes being copied.
enum UpdateInstaller {
    private nonisolated static let log = Logger(subsystem: "io.zephra", category: "update")

    /// Puts the Zephra inside `image` where `bundle` is, and answers where it now is.
    ///
    /// `nonisolated` and blocking: every step shells out, and the caller runs it in a detached
    /// task. Nothing here touches the interface.
    nonisolated static func install(
        image: URL, manifest: ReleaseManifest, bundle: URL, identifier: String
    ) throws -> URL {
        let mount = image.deletingLastPathComponent().appending(path: "mount-\(manifest.build)")
        try mountImage(image, at: mount)
        defer { detach(mount) }
        let candidate = mount.appending(path: "Zephra.app")
        try verify(candidate, manifest: manifest, identifier: identifier)
        return try swap(candidate, into: bundle)
    }

    /// Attaches `image` at a mount point of ours, having cleared whatever a previous run left.
    private nonisolated static func mountImage(_ image: URL, at mount: URL) throws {
        detach(mount)
        try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let result = try UpdateTool.run(
            "/usr/bin/hdiutil",
            [
                "attach", image.path(percentEncoded: false), "-nobrowse", "-readonly",
                "-noautoopen", "-mountpoint", mount.path(percentEncoded: false),
            ])
        guard result.succeeded else { throw UpdateInstallError.mountFailed(reason: result.lastLine) }
    }

    /// Unmounts, and only logs a failure: the update is already in place by then, and a mount
    /// point left behind costs the next install nothing — it detaches before it attaches.
    private nonisolated static func detach(_ mount: URL) {
        guard FileManager.default.fileExists(atPath: mount.path(percentEncoded: false)) else { return }
        let result = try? UpdateTool.run(
            "/usr/bin/hdiutil", ["detach", mount.path(percentEncoded: false), "-quiet"])
        if result?.succeeded != true {
            log.error("update: the disk image could not be detached: \(result?.lastLine ?? "unknown", privacy: .public)")
        }
        try? FileManager.default.removeItem(at: mount)
    }

    /// Steps 3 to 5: aside, copy, verify, and back again if any of it fails.
    private nonisolated static func swap(_ candidate: URL, into bundle: URL) throws -> URL {
        let files = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        guard files.isWritableFile(atPath: parent.path(percentEncoded: false)) else {
            throw UpdateInstallError.cannotReplaceItself(folder: parent.path(percentEncoded: false))
        }
        let aside = parent.appending(path: bundle.deletingPathExtension().lastPathComponent + ".previous.app")
        try? files.removeItem(at: aside)
        do {
            try files.moveItem(at: bundle, to: aside)
        } catch {
            throw UpdateInstallError.copyFailed(reason: error.localizedDescription)
        }
        do {
            let copy = try UpdateTool.run(
                "/usr/bin/ditto",
                [candidate.path(percentEncoded: false), bundle.path(percentEncoded: false)])
            guard copy.succeeded else { throw UpdateInstallError.copyFailed(reason: copy.lastLine) }
            let signature = try UpdateTool.run(
                "/usr/bin/codesign", ["--verify", "--strict", bundle.path(percentEncoded: false)])
            guard signature.succeeded else {
                throw UpdateInstallError.signatureInvalid(reason: signature.lastLine)
            }
        } catch {
            try? files.removeItem(at: bundle)
            try? files.moveItem(at: aside, to: bundle)
            throw error
        }
        log.info("update: installed over \(bundle.lastPathComponent, privacy: .public)")
        return bundle
    }
}
