import AppKit
import Foundation
import ZephraCore
import ZephraEngine

/// The drawn pictures a preview library points at, and the gradient every preview picture is.
///
/// Apart from `PreviewImages` so the records a preview holds in memory and the files a preview
/// library reads from disk each fit on one screen; the gradient sits here because these are the
/// callers that vary its hue.
extension PreviewImages {
    /// `count` drawn pictures on disk, for a preview library to point at.
    ///
    /// Real files, because a thumbnail is baked by Image I/O from a path: an invented library
    /// whose items pointed nowhere would show a wall of grey, which is exactly the thing a
    /// screenshot of the grid is meant to show is not happening. They go in the temporary
    /// directory and nothing ever deletes them, which is the temporary directory's job.
    ///
    /// Each is drawn at a different hue so the grid reads as a set of different images rather
    /// than one image repeated.
    static func libraryFiles(count: Int) -> [URL] {
        let folder = URL.temporaryDirectory.appending(path: "Zephra Previews", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (0..<count).compactMap { offset in
            let url = folder.appending(path: "zephra-preview-\(offset).png")
            guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return url
            }
            let data = gradientPNG(size: ImageSize(width: 512, height: 512), hue: Double(offset) * 0.13)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            return url
        }
    }

    /// An invented library whose images are pictures on disk, for previews and screenshots.
    ///
    /// The one call every `#Preview` in the library makes, so none of them has to remember to
    /// supply the files and none of them shows a wall of grey by accident.
    static func library(count: Int = 38) -> LibraryIndex {
        LibraryIndex.preview(count: count, pictures: libraryFiles(count: count + 3))
    }

    /// PNG bytes for a dusk-coloured gradient with a low horizon, drawn with Core Graphics.
    /// `hue` rotates the whole palette, so a set of these reads as different pictures.
    static func gradientPNG(size: ImageSize, hue: Double = 0) -> Data {
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        draw(in: context, rect: rect, hue: hue)
        guard let cgImage = context.makeImage() else { return Data() }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    private static func draw(in context: CGContext, rect: CGRect, hue: Double) {
        let colors = [
            rotated(red: 0.07, green: 0.09, blue: 0.14, by: hue),
            rotated(red: 0.22, green: 0.20, blue: 0.28, by: hue),
            rotated(red: 0.91, green: 0.66, blue: 0.35, by: hue),
            rotated(red: 0.17, green: 0.18, blue: 0.23, by: hue),
        ]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 0.52, 0.80, 0.83]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: rect.maxY),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
        context.setFillColor(CGColor(red: 0.97, green: 0.85, blue: 0.66, alpha: 0.9))
        let beam = rect.width * 0.045
        context.fillEllipse(in: CGRect(
            x: rect.midX - beam / 2,
            y: rect.height * 0.22,
            width: beam,
            height: beam
        ))
    }

    /// One of the palette's colours, turned `by` around the wheel and back to RGB.
    ///
    /// Through hue rather than by adding to each channel, so a dark colour stays dark and the
    /// dusk keeps its shape: the pictures differ in colour and agree in composition, which is
    /// what a wall of thumbnails from one model actually looks like.
    private static func rotated(red: Double, green: Double, blue: Double, by hue: Double) -> CGColor {
        let colour = NSColor(
            calibratedRed: red, green: green, blue: blue, alpha: 1
        ).usingColorSpace(.deviceRGB) ?? .black
        let turned = NSColor(
            calibratedHue: (colour.hueComponent + hue).truncatingRemainder(dividingBy: 1),
            saturation: colour.saturationComponent,
            brightness: colour.brightnessComponent,
            alpha: 1
        )
        return turned.cgColor
    }
}
