import AppKit
import Foundation
import ZephraCore

/// Pictures drawn in-process so previews and the interface-only launch mode have something
/// to letterbox. Nothing here reaches the model or the network.
enum PreviewImages {
    /// A finished image record wrapping a drawn gradient, for previews of the done state.
    static func sample(
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        prompt: String = "A lighthouse at dusk, fog rolling in over black rocks"
    ) -> GeneratedImage {
        GeneratedImage(
            pngData: gradientPNG(size: size),
            settings: GenerationSettings(
                prompt: prompt,
                size: size,
                steps: 9,
                guidance: 0,
                seed: 8_123_447_209_115_662
            ),
            modelID: ModelCatalog.default.id,
            duration: .seconds(19) + .milliseconds(400)
        )
    }

    /// PNG bytes for a dusk-coloured gradient with a low horizon, drawn with Core Graphics.
    static func gradientPNG(size: ImageSize) -> Data {
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
        draw(in: context, rect: rect)
        guard let cgImage = context.makeImage() else { return Data() }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    private static func draw(in context: CGContext, rect: CGRect) {
        let colors = [
            CGColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1),
            CGColor(red: 0.22, green: 0.20, blue: 0.28, alpha: 1),
            CGColor(red: 0.91, green: 0.66, blue: 0.35, alpha: 1),
            CGColor(red: 0.17, green: 0.18, blue: 0.23, alpha: 1),
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
}
