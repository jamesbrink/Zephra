import AppKit
import Testing
import ZephraTestSupport
@testable import Zephra

@Suite("A copied picture on the pasteboard")
struct PasteboardImageTests {
    @Test("carries the PNG, the file's URL, and a TIFF made only when asked for")
    func everyForm() throws {
        let scratch = Scratch()
        let file = try scratch.make("one.png")
        let png = try #require(Self.png(width: 3, height: 2))
        try png.write(to: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([PasteboardImage.item(png: png, file: file)])

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.data(forType: .png) == png)
        #expect(item.string(forType: .fileURL) == file.absoluteString)
        #expect(item.types.contains(.tiff))
        let tiff = try #require(item.data(forType: .tiff))
        let rep = try #require(NSBitmapImageRep(data: tiff))
        #expect(rep.pixelsWide == 3 && rep.pixelsHigh == 2)
    }

    @Test("a picture with no file yet offers no file URL")
    func noFile() throws {
        let png = try #require(Self.png(width: 2, height: 2))
        let item = PasteboardImage.item(png: png, file: nil)
        #expect(!item.types.contains(.fileURL))
        #expect(item.types.contains(.png) && item.types.contains(.tiff))
    }

    private static func png(width: Int, height: Int) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        return rep?.representation(using: .png, properties: [:])
    }
}
