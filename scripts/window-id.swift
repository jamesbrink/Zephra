// Prints the CoreGraphics window id of Zephra's largest on-screen window, or nothing.
//
// `screencapture -l <id>` needs this number, and it is the only capture form that photographs
// the window itself rather than the rectangle of screen it happens to occupy: a region capture
// of an occluded window returns whatever is in front of it, which in a shared session means
// somebody else's windows land in out/.
//
// System Events' `id of window 1` is an accessibility identifier, not this, which is why
// reading it there never worked.
import CoreGraphics
import Foundation

let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Zephra"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

let candidates = windows.compactMap { window -> (id: CGWindowID, area: CGFloat)? in
    guard window[kCGWindowOwnerName as String] as? String == name,
        let number = window[kCGWindowNumber as String] as? CGWindowID,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
        let width = bounds["Width"], let height = bounds["Height"],
        // Panels, tooltips and the like are small; the document window is not.
        width > 200, height > 200
    else { return nil }
    return (number, width * height)
}

guard let biggest = candidates.max(by: { $0.area < $1.area }) else { exit(1) }
print(biggest.id)
