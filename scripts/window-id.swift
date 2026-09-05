// Prints the CoreGraphics window id of one of Zephra's on-screen windows, or nothing.
//
// usage: swift window-id.swift [owner] [title]
//
// With no title, the owner's largest window: the document window, since panels and tooltips
// are small. With a title, the owner's window whose title is exactly that — "General" for the
// Settings window on its General tab, say — so a window `make screenshot` cannot otherwise
// tell from the main one can be photographed (`make screenshot WINDOW=General`).
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
let title = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

let candidates = windows.compactMap { window -> (id: CGWindowID, area: CGFloat)? in
    guard window[kCGWindowOwnerName as String] as? String == name,
        let number = window[kCGWindowNumber as String] as? CGWindowID,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
        let width = bounds["Width"], let height = bounds["Height"]
    else { return nil }
    if let title {
        guard window[kCGWindowName as String] as? String == title else { return nil }
    } else {
        // Panels, tooltips and the like are small; the document window is not.
        guard width > 200, height > 200 else { return nil }
    }
    return (number, width * height)
}

guard let biggest = candidates.max(by: { $0.area < $1.area }) else { exit(1) }
print(biggest.id)
