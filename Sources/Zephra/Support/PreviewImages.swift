import AppKit
import Foundation
import ZephraCore
import ZephraEngine

/// Pictures drawn in-process so previews and the interface-only launch mode have something
/// to letterbox. Nothing here reaches the model or the network.
enum PreviewImages {
    /// A finished image record wrapping a drawn gradient, for previews of the done state.
    static func sample(
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        prompt: String = "A lighthouse at dusk, fog rolling in over black rocks",
        reference: Data? = nil
    ) -> GeneratedImage {
        GeneratedImage(
            pngData: gradientPNG(size: size),
            settings: GenerationSettings(
                prompt: prompt,
                size: size,
                steps: 9,
                guidance: 0,
                seed: 8_123_447_209_115_662,
                referenceImage: reference
            ),
            modelID: ModelCatalog.default.id,
            duration: .seconds(19) + .milliseconds(400)
        )
    }

    /// One press of Generate's worth of images, newest first as `history` holds them, all
    /// sharing a batch id so the strip under the capsule has a run to draw.
    static func run(
        of count: Int,
        prompt: String = "a red bicycle against a limestone wall, hard afternoon shadow"
    ) -> [GeneratedImage] {
        let batch = UUID()
        let size = ImageSize(width: 1024, height: 1024)
        let data = gradientPNG(size: size)
        let now = Date()
        return (0..<count).reversed().map { index in
            GeneratedImage(
                pngData: data,
                settings: GenerationSettings(
                    prompt: prompt,
                    size: size,
                    steps: 4,
                    guidance: 0,
                    seed: 8_123_447_209_115_662 &+ UInt64(index)
                ),
                modelID: ModelCatalog.default.id,
                createdAt: now.addingTimeInterval(-Double(count - index) * 7),
                duration: .seconds(6) + .milliseconds(900),
                batchID: batch
            )
        }
    }

    /// A small picture to sit in the reference well: the same gradient at a modest size.
    static func referencePNG() -> Data {
        gradientPNG(size: ImageSize(width: 512, height: 384))
    }

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
