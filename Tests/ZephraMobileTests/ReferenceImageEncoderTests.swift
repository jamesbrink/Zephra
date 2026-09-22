import Foundation
import Testing
import UIKit

@testable import ZephraMobile

/// A picture out of a phone's camera is twelve megapixels; what crosses the link is a PNG at
/// most 1024 pixels an edge. This is that promise, kept.
@MainActor
@Suite("A picture handed in comes out as a PNG inside the budget")
struct ReferenceImageEncoderTests {
    /// A picture of a given size, drawn rather than read, so the suite carries no fixture.
    private func image(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        let drawn = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return drawn.pngData() ?? Data()
    }

    @Test("A 3000-pixel photograph comes back inside 1024 on its long edge")
    func aLargePictureIsScaledDown() throws {
        let picture = try #require(
            ReferenceImageEncoder.picture(from: image(width: 3000, height: 2000)))
        let size = try #require(picture.size, "the encoder measures what it wrote")
        #expect(max(size.width, size.height) <= 1024)
        #expect(size.width > size.height)
    }

    @Test("What comes back is a PNG")
    func theBytesArePNG() throws {
        let picture = try #require(
            ReferenceImageEncoder.picture(from: image(width: 3000, height: 2000)))
        #expect(picture.data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test("The shape that comes back is the shape of the bytes")
    func theSizeDescribesTheBytes() throws {
        let picture = try #require(
            ReferenceImageEncoder.picture(from: image(width: 1200, height: 1600)))
        let decoded = try #require(UIImage(data: picture.data))
        let size = try #require(picture.size)
        #expect(Int(decoded.size.width) == size.width)
        #expect(Int(decoded.size.height) == size.height)
    }

    @Test("Bytes that are not a picture come back as nothing")
    func rubbishIsRefused() {
        #expect(ReferenceImageEncoder.picture(from: Data("not a picture".utf8)) == nil)
    }
}
