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
try write(dark, pixels: 256, to: website.appending(path: "icon-dark.png"))
try write(light, pixels: 256, to: website.appending(path: "icon-light.png"))
try write(mark, pixels: 256, to: website.appending(path: "mark.png"))
