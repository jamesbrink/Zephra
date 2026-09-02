#!/usr/bin/env swift
//
// Renders Zephra's app icon at every size AppIcon.appiconset asks for.
//
//   swift scripts/make-icon.swift        (or: make icon)
//
// The look is "darkroom": a graphite plate lit from below by a safelight, with
// a single white Z. Geometry follows Apple's macOS icon grid — an 824 pt
// rounded square with a 185 pt corner radius, centred in a 1024 pt canvas, the
// surrounding margin left to the drop shadow.

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry, in canvas units

let canvas: CGFloat = 1024
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

/// The Z, as an outline in canvas units: a geometric three-stroke letter, two
/// bars and a diagonal, all of the same weight.
func zPath(in box: CGRect) -> CGPath {
    let (w, h, t) = (box.width, box.height, box.width * 0.225)
    // Where the diagonal meets the bottom bar, solved so the diagonal measures
    // `t` across its width just as the bars do. Converges in a couple of passes.
    var inner = t
    for _ in 0..<8 {
        let rise = h - 2 * t
        let run = w - inner
        inner = t * (rise * rise + run * run).squareRoot() / rise
    }
    let outer = w - inner  // where it meets the top bar
    let p = CGMutablePath()
    let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: box.minX + x, y: box.minY + y) }
    p.move(to: point(0, h))
    p.addLine(to: point(w, h))
    p.addLine(to: point(w, h - t))
    p.addLine(to: point(inner, t))
    p.addLine(to: point(w, t))
    p.addLine(to: point(w, 0))
    p.addLine(to: point(0, 0))
    p.addLine(to: point(0, t))
    p.addLine(to: point(outer, h - t))
    p.addLine(to: point(0, h - t))
    p.closeSubpath()
    return p
}

// MARK: - Palette

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

/// Graphite #17181B, spread into a top-lit gradient that averages back to it.
let plateTop = rgb(0.121, 0.126, 0.141)
let plateBottom = rgb(0.063, 0.067, 0.078)
/// Safelight amber #E8A85A.
let amber: (CGFloat, CGFloat, CGFloat) = (0.910, 0.659, 0.353)

func amberRamp(_ peak: CGFloat) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: [
            rgb(amber.0, amber.1, amber.2, peak),
            rgb(amber.0, amber.1, amber.2, peak * 0.42),
            rgb(amber.0, amber.1, amber.2, 0),
        ] as CFArray,
        locations: [0, 0.45, 1]
    )!
}

// MARK: - Drawing

func drawIcon(into ctx: CGContext, pixels: CGFloat) {
    ctx.scaleBy(x: pixels / canvas, y: pixels / canvas)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let shape = CGPath(
        roundedRect: plate, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
    )

    // Drop shadow, laid down by filling the plate once behind everything else.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(plateBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Graphite base.
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: space, colors: [plateTop, plateBottom] as CFArray, locations: [0, 1])!,
        start: CGPoint(x: 0, y: plate.maxY),
        end: CGPoint(x: 0, y: plate.minY),
        options: []
    )

    // Safelight: a wide wash low in the frame with a brighter core at its heart,
    // added as light rather than mixed as pigment so it stays amber, not brown.
    let lamp = CGPoint(x: plate.midX, y: plate.minY + plate.height * 0.125)
    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(
        amberRamp(0.30), startCenter: lamp, startRadius: 0,
        endCenter: lamp, endRadius: plate.width * 0.70, options: []
    )
    ctx.drawRadialGradient(
        amberRamp(0.34), startCenter: lamp, startRadius: 0,
        endCenter: lamp, endRadius: plate.width * 0.24, options: []
    )
    ctx.setBlendMode(.normal)

    // The glyph.
    let box = CGRect(
        x: plate.midX - 180, y: plate.midY - 188 + plate.height * 0.06, width: 360, height: 376
    )
    ctx.addPath(zPath(in: box))
    ctx.setFillColor(rgb(1, 1, 1, 0.9))
    ctx.fillPath()

    // A hairline of light along the top edge only, so the plate reads as a surface
    // catching the room light rather than as a ringed sticker.
    ctx.clip(to: CGRect(x: 0, y: plate.midY, width: canvas, height: plate.maxY - plate.midY))
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.setLineWidth(5)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(into: ctx, pixels: CGFloat(pixels))
    return ctx.makeImage()!
}

// MARK: - Emit every entry Contents.json lists

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appending(path: "Sources/Zephra/Resources/Assets.xcassets/AppIcon.appiconset")
let manifest = try Data(contentsOf: set.appending(path: "Contents.json"))
let images =
    (try JSONSerialization.jsonObject(with: manifest) as! [String: Any])["images"] as! [[String: String]]

for entry in images {
    guard let name = entry["filename"], let size = entry["size"], let scale = entry["scale"] else {
        continue
    }
    let side = Double(size.split(separator: "x")[0])!
    let factor = Double(scale.dropLast())!
    let pixels = Int((side * factor).rounded())
    let image = render(pixels: pixels)
    let url = set.appending(path: name)
    let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(out, image, nil)
    guard CGImageDestinationFinalize(out) else { fatalError("could not write \(name)") }
    print("\(name)  \(pixels)x\(pixels)")
}
