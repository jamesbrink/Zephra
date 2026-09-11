#!/usr/bin/env swift

// Export the selected Zephyr masters into the app catalog and website.
// Run from the repository root: make icon. No artwork is synthesized here.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masters = root.appending(path: "design/branding/zephyr")
let catalog = root.appending(path: "Sources/Zephra/Resources/Assets.xcassets/AppIcon.appiconset")
let phone = root.appending(path: "Sources/ZephraMobile/Resources/Assets.xcassets/AppIcon.appiconset")
let website = root.appending(path: "product-mockups/public/images")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func read(_ name: String) throws -> CGImage {
  let url = masters.appending(path: name)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    image.width == image.height, image.width >= 1024
  else {
    throw NSError(
      domain: "ZephraIcon", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Invalid square master: \(url.path)"])
  }
  return image
}

func write(_ image: CGImage, pixels: Int, to url: URL) throws {
  guard
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else { throw NSError(domain: "ZephraIcon", code: 2) }
  context.interpolationQuality = .high
  context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
  guard let output = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw NSError(domain: "ZephraIcon", code: 3) }
  CGImageDestinationAddImage(destination, output, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "ZephraIcon", code: 4)
  }
  print("\(url.lastPathComponent)  \(pixels)×\(pixels)")
}


// iOS wants the opposite of what a Mac icon is. A Mac icon is a rounded shape floating in a
// transparent square, and the master is drawn that way; App Store Connect refuses a phone
// icon with any alpha at all ("Invalid large app icon ... can't be transparent or contain an
// alpha channel", error 90717) and wants the artwork edge to edge, since iOS applies its own
// mask. So the master's artwork is found, cropped out of its margin, and drawn opaque. The
// corners the master rounded are filled with the artwork's own edge colour and then cut away
// again by iOS, whose mask is the wider radius of the two.
func artworkBounds(of image: CGImage) -> CGRect {
  let width = image.width, height = image.height
  guard
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { return CGRect(x: 0, y: 0, width: width, height: height) }
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
    return CGRect(x: 0, y: 0, width: width, height: height)
  }
  var minX = width, minY = height, maxX = -1, maxY = -1
  for y in 0..<height {
    for x in 0..<width where data[y * width * 4 + x * 4 + 3] >= 128 {
      minX = min(minX, x); maxX = max(maxX, x)
      minY = min(minY, y); maxY = max(maxY, y)
    }
  }
  guard maxX >= minX, maxY >= minY else {
    return CGRect(x: 0, y: 0, width: width, height: height)
  }
  // Square and centred: a crop one pixel wider than tall would stretch the mark.
  let side = max(maxX - minX + 1, maxY - minY + 1)
  let centreX = Double(minX + maxX + 1) / 2, centreY = Double(minY + maxY + 1) / 2
  let origin = CGPoint(
    x: min(max(centreX - Double(side) / 2, 0), Double(width - side)),
    y: min(max(centreY - Double(side) / 2, 0), Double(height - side)))
  return CGRect(x: origin.x, y: origin.y, width: Double(side), height: Double(side))
}

// The colour to fill behind the artwork: the mean of what it is made of at the middle of its
// four edges, which is its background rather than whatever the mark is drawn in.
func edgeColour(of image: CGImage) -> CGColor {
  let width = image.width, height = image.height
  guard
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let _ = Optional(context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))),
    let data = context.data?.assumingMemoryBound(to: UInt8.self)
  else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
  let inset = max(width / 20, 1)
  let samples = [
    (inset, height / 2), (width - 1 - inset, height / 2),
    (width / 2, inset), (width / 2, height - 1 - inset),
  ]
  var total = (r: 0.0, g: 0.0, b: 0.0)
  for (x, y) in samples {
    let offset = y * width * 4 + x * 4
    let alpha = max(Double(data[offset + 3]) / 255, 0.0001)
    total.r += Double(data[offset]) / 255 / alpha
    total.g += Double(data[offset + 1]) / 255 / alpha
    total.b += Double(data[offset + 2]) / 255 / alpha
  }
  let count = Double(samples.count)
  return CGColor(
    srgbRed: min(total.r / count, 1), green: min(total.g / count, 1),
    blue: min(total.b / count, 1), alpha: 1)
}

func writePhone(_ image: CGImage, pixels: Int, to url: URL) throws {
  let bounds = artworkBounds(of: image)
  guard let artwork = image.cropping(to: bounds) else { throw NSError(domain: "ZephraIcon", code: 6) }
  guard
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { throw NSError(domain: "ZephraIcon", code: 2) }
  let square = CGRect(x: 0, y: 0, width: pixels, height: pixels)
  context.setFillColor(edgeColour(of: artwork))
  context.fill(square)
  context.interpolationQuality = .high
  context.draw(artwork, in: square)
  guard let output = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw NSError(domain: "ZephraIcon", code: 3) }
  CGImageDestinationAddImage(destination, output, nil)
  guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "ZephraIcon", code: 4) }
  print("\(url.lastPathComponent)  \(pixels)×\(pixels)  opaque, full bleed")
}

// Validate all masters before replacing any generated assets.
let dark = try read("icon-dark.png")
let light = try read("icon-light.png")
let mark = try read("mark.png")
let manifest = try Data(contentsOf: catalog.appending(path: "Contents.json"))
let entries =
  (try JSONSerialization.jsonObject(with: manifest) as! [String: Any])["images"]
  as! [[String: String]]
for entry in entries {
  guard let name = entry["filename"], let size = entry["size"], let scale = entry["scale"],
    let side = Double(size.split(separator: "x")[0]), let factor = Double(scale.dropLast())
  else { throw NSError(domain: "ZephraIcon", code: 5) }
  try write(dark, pixels: Int(side * factor), to: catalog.appending(path: name))
}
// The phone takes one square and derives every size it shows from it, which is why its
// catalog names a single file rather than the ten the Mac's does. The same master, so the
// two apps wear the same mark -- but drawn the way iOS wants it rather than the way macOS
// does, which is what `writePhone` is for.
try writePhone(dark, pixels: 1024, to: phone.appending(path: "icon_1024x1024.png"))
try write(dark, pixels: 256, to: website.appending(path: "icon-dark.png"))
try write(light, pixels: 256, to: website.appending(path: "icon-light.png"))
try write(mark, pixels: 256, to: website.appending(path: "mark.png"))
