import Foundation
import UIKit

/// The pictures the `viewer` state has to show, drawn at launch.
///
/// Blobs fail on a frozen client, so every other state's viewer says the picture is not on
/// this phone — which photographs the offline path and nothing else. The viewer is about
/// paging, pinching and pulling, and those need a picture under the finger, so this one state
/// draws one per fixture entry into a folder the catalog's `FileStore` reads before it asks
/// the Mac for anything. Under the temporary directory and emptied on every launch, so the
/// rule that a frozen build writes nothing that outlives it still holds.
///
/// Drawn rather than bundled, for the reason `frame()` is: a photograph of one particular
/// run would prove nothing about a viewer that shows whatever arrives. What matters is that
/// each page is unmistakably itself — a number a swipe can count by — and has edges a zoom
/// can be seen against. The fixture's clip gets its poster and, beside it under the sidecar's
/// name, a short MP4 of the same page with a bar sweeping across it (`MobilePreview+Clip`),
/// so the clip's page plays and a pull over it can be tried.
extension MobilePreview {
    /// The folder of drawn pictures, or nil for every state but `viewer`.
    static func pictureFolder() -> URL? {
        guard state == .viewer else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ZephraPreviewFiles", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, entry) in library().enumerated() {
            let size = CGSize(width: entry.width, height: entry.height)
            let page = page(number: index + 1, size: size)
            try? page.pngData()?.write(to: folder.appending(path: entry.fileName))
            if entry.isVideo {
                clip(number: index + 1, size: size,
                    to: folder.appending(path: LibraryCatalog.clipName(of: entry.fileName)))
            }
        }
        return folder
    }

    /// One page: a gradient, a fine grid, and its number, at the entry's own size. `sweep` is
    /// how far across a bar is drawn, for a clip's frames; nil draws none.
    static func page(number: Int, size: CGSize, sweep: CGFloat? = nil) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors =
                [
                    UIColor(hue: CGFloat(number) * 0.17, saturation: 0.55, brightness: 0.35,
                        alpha: 1).cgColor,
                    UIColor(hue: CGFloat(number) * 0.17 + 0.08, saturation: 0.45,
                        brightness: 0.85, alpha: 1).cgColor,
                ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
            {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: size.height),
                    options: [])
            }
            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.cgContext.setLineWidth(1)
            for step in stride(from: 0, through: Int(max(size.width, size.height)), by: 64) {
                let line = CGFloat(step) + 0.5
                context.cgContext.move(to: CGPoint(x: line, y: 0))
                context.cgContext.addLine(to: CGPoint(x: line, y: size.height))
                context.cgContext.move(to: CGPoint(x: 0, y: line))
                context.cgContext.addLine(to: CGPoint(x: size.width, y: line))
            }
            context.cgContext.strokePath()
            let label = NSAttributedString(
                string: "\(number)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: size.height * 0.5, weight: .black),
                    .foregroundColor: UIColor.white,
                ])
            let bounds = label.size()
            label.draw(at: CGPoint(
                x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
            if let sweep {
                context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                context.cgContext.fill(
                    CGRect(x: sweep * size.width - 8, y: 0, width: 16, height: size.height))
            }
        }
    }
}
