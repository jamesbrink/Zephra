import Foundation
import ZephraCore

/// Taking an image out of the library for good.
extension ImageLibrary {
    /// Moves a file to the Trash, so deleting an image is always something the user can undo
    /// from the Finder.
    ///
    /// Not every location has a Trash to move to — a volume without one, and some temporary
    /// directories — and `trashItem` fails there. Leaving the file behind after the interface
    /// has already dropped the image would be worse than the delete being final, so in that
    /// case it is removed outright.
    public func discard(_ url: URL) throws {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try FileManager.default.removeItem(at: url)
        }
    }
}
