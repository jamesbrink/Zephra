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
/// can be seen against.
extension MobilePreview {
    /// The folder of drawn pictures, or nil for every state but `viewer`.
    static func pictureFolder() -> URL? {
        guard state == .viewer else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "ZephraPreviewFiles", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, entry) in library().enumerated() where !entry.isVideo {
            let png = picture(number: index + 1, width: entry.width, height: entry.height)
            try? png.write(to: folder.appending(path: entry.fileName))
        }
        return folder
    }

    /// One page: a gradient, a fine grid, and its number, at the entry's own size.
    private static func picture(number: Int, width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { context in
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
            for step in stride(from: 0, through: max(width, height), by: 64) {
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
        }
        return image.pngData() ?? Data()
    }
}
