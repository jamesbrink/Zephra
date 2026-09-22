import AppKit
import CoreGraphics
import Foundation
import Observation
import ZephraEngine

/// Decoded thumbnails for the images on disk, in memory in front of the folder that keeps them.
///
/// Two caches, one behind the other: this one holds the pixels a grid is drawing right now and
/// is bounded by how much they weigh, and `ThumbnailFolder` holds the baked files, which
/// survive a relaunch. A miss here costs a file read; a miss in both costs a decode of the
/// full-size picture, which is the thing worth never doing twice.
///
/// Separate from `ImageCache`, which keys on the identity of an image made this session and
/// holds its full-resolution pixels. This one keys on a file's path and state, holds nothing
/// bigger than 800 pixels, and knows nothing about a generation.
@MainActor
@Observable
final class ThumbnailCache {
    /// Roughly ninety-six megabytes, which is about three hundred of the largest bucket.
    private static let memoryLimit = 96 * 1024 * 1024

    private let memory = NSCache<NSString, DrawnPicture>()
    /// The baked files behind this cache. Not private, because the companion link asks the same
    /// folder for the same thumbnails: two folders over one directory would be two gates and
    /// twice the concurrent decodes for the same files.
    let folder: ThumbnailFolder

    /// The bakes running right now, so two cells asking for the same picture are one decode.
    @ObservationIgnored private var inFlight: [ThumbnailKey: Task<CGImage?, Never>] = [:]

    /// A cache over one thumbnail folder. One instance lives for the life of the window.
    init(folder: ThumbnailFolder = ThumbnailFolder()) {
        self.folder = folder
        memory.totalCostLimit = Self.memoryLimit
    }

    /// The thumbnail already in memory, or nil. Cheap enough to call from `body`, which is what
    /// lets a cell that has one draw it on the first frame rather than after a flash of nothing.
    func cached(_ item: LibraryItem, size: ThumbnailSize) -> DrawnPicture? {
        memory.object(forKey: ThumbnailKey(item, size: size).cacheKey)
    }

    /// The thumbnail for one image, from memory, from the folder, or freshly baked.
    ///
    /// The bake is detached, so a caller that is cancelled — a cell scrolled off, a size bucket
    /// changed under it — does not cancel it. Half a decoded picture is worth nothing to
    /// anybody, and the next cell to ask will want the whole one. What cancellation does mean
    /// is that this caller stops caring: the pixels are put in memory either way and nil comes
    /// back, so a stale image is never handed to a view that has moved on.
    func load(_ item: LibraryItem, size: ThumbnailSize) async -> DrawnPicture? {
        let key = ThumbnailKey(item, size: size)
        if let hit = memory.object(forKey: key.cacheKey) { return hit }
        let task = inFlight[key] ?? detachedBake(key, of: item.url, pixels: size.pixels)
        inFlight[key] = task
        let baked = await task.value
        inFlight[key] = nil
        guard let baked else { return nil }
        let image = store(baked, for: key)
        return Task.isCancelled ? nil : image
    }

    /// Starts baking images that are about to be needed, and returns at once.
    ///
    /// SwiftUI's lazy grids have no prefetch hook, so the grid says when a section's last row
    /// has appeared and this gets a head start on what is below it. Anything already in memory
    /// or already being baked is skipped, so calling it repeatedly as a scroll goes by is free.
    func warm(_ items: [LibraryItem], size: ThumbnailSize) {
        for item in items {
            let key = ThumbnailKey(item, size: size)
            guard memory.object(forKey: key.cacheKey) == nil, inFlight[key] == nil else { continue }
            Task { _ = await load(item, size: size) }
        }
    }

    /// Throws away thumbnails nothing has asked for in a month. Called once, at launch.
    func sweep() {
        let folder = folder
        Task.detached(priority: .background) { await folder.sweep() }
    }

    /// A bake that outlives whoever asked for it.
    private func detachedBake(
        _ key: ThumbnailKey,
        of url: URL,
        pixels: Int
    ) -> Task<CGImage?, Never> {
        let folder = folder
        return Task.detached(priority: .utility) {
            await folder.image(for: key, of: url, pixels: pixels)
        }
    }

    /// Puts one baked picture in memory, costed by what it actually weighs so the limit means
    /// megabytes rather than a guess at how many images make up a screenful.
    ///
    /// The `NSImage` is given half the pixels as its point size, which is what makes it a 2x
    /// representation: SwiftUI then draws it at its natural size on a Retina screen without
    /// scaling anything.
    @discardableResult
    private func store(_ image: CGImage, for key: ThumbnailKey) -> DrawnPicture {
        let points = CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let made = DrawnPicture(image, points: points)
        memory.setObject(made, forKey: key.cacheKey, cost: image.width * image.height * 4)
        return made
    }
}
