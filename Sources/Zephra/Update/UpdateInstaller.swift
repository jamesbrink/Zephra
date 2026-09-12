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
///    ticket with no network — the team identifier says it is ours rather than merely somebody
///    notarized, and the `Info.plist` has to be the identifier and the build the manifest
///    promised. A download that fails any of these is discarded with this copy untouched.
/// 3. **Rename this bundle aside** rather than deleting it: a running bundle may be renamed,
///    since the executable is mapped by inode, and the rename is what makes the swap
///    reversible.
/// 4. **`ditto`**, which is what `create-dmg.sh` already trusts to carry extended attributes,
///    resource forks and symbolic links — a `copyItem` that quietly drops one of those leaves
///    an app that will not launch. Then `codesign --verify` on the copy, because a copy is a
///    new set of bytes.
/// 5. **Roll back** on any failure, and *check that the rollback landed*: the one outcome
///    worth refusing to paper over is a Mac left with no `Zephra.app` at all.
///
/// No quarantine handling is needed and none is done: `LSFileQuarantineEnabled` is unset, the
/// files on a mounted image carry no quarantine attribute of their own, and `spctl` has already
/// run Gatekeeper's assessment over the very bytes being copied.
enum UpdateInstaller {
    nonisolated static let log = Logger(subsystem: "io.zephra", category: "update")

    /// Puts the Zephra inside `image` where `bundle` is, and answers where it now is.
    ///
    /// `nonisolated` and blocking: every step shells out, and the caller runs it in a detached
    /// task. Nothing here touches the interface.
    nonisolated static func install(
        image: URL, manifest: ReleaseManifest, bundle: URL, identifier: String,
        overridden: Bool = false
    ) throws -> URL {
        // The build is a path component below. It has been a twelve-digit stamp since the feed
        // was read — nothing else is ever `isNewer` — but this is the file system, so the
        // manifest's word is checked again here rather than trusted across two call sites.
        guard ReleaseManifest.isStamp(manifest.build) else { throw UpdateInstallError.notAZephra }
        let mount = image.deletingLastPathComponent().appending(path: "mount-\(manifest.build)")
        try mountImage(image, at: mount)
        defer { detach(mount) }
        let candidate = mount.appending(path: "Zephra.app")
        try verify(candidate, manifest: manifest, identifier: identifier, overridden: overridden)
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
            throw rollingBack(from: aside, to: bundle, after: error)
        }
        log.info("update: installed over \(bundle.lastPathComponent, privacy: .public)")
        return bundle
    }

    /// Puts the original back and answers what to throw: `error` when the app is where it was,
    /// and a sentence naming the aside path when it is not.
    ///
    /// Both steps used to be `try?`, which is wrong in exactly one case and badly: a partial
    /// copy that cannot be removed makes the move back fail too, and the person is then told
    /// the update "could not be put in place" while their Applications folder holds no Zephra
    /// at all. There is nothing left to do for them automatically at that point — so the
    /// sentence says where their app is and what to rename.
    private nonisolated static func rollingBack(
        from aside: URL, to bundle: URL, after error: any Error
    ) -> any Error {
        let files = FileManager.default
        try? files.removeItem(at: bundle)
        try? files.moveItem(at: aside, to: bundle)
        guard !files.fileExists(atPath: bundle.path(percentEncoded: false)) else { return error }
        log.error("update: the rollback did not land; the app is at \(aside.path(percentEncoded: false), privacy: .public)")
        return UpdateInstallError.rollbackFailed(aside: aside.path(percentEncoded: false))
    }
}
