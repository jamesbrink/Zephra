import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZephraCore

@testable import ZephraBackendLTX2

@Suite("what the engine's settings become on their way into the pipeline")
struct LTX2RequestMapperTests {
    static let descriptor = ModelCatalog.ltx2Distilled4bit

    /// A one-pixel PNG, which is all the mapper's decode needs to succeed.
    static func png() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func settings(reference: Data?, strength: Double) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImage = reference
        settings.referenceStrength = strength
        return settings
    }

    @Test("no picture is no first frame, whatever strength the settings happen to carry")
    func noPictureHoldsNothing() throws {
        for strength in [0.0, 0.5, 1.0] {
            let request = try LTX2RequestMapper.request(
                for: Self.settings(reference: nil, strength: strength), descriptor: Self.descriptor)
            #expect(request.firstFrame == nil, Comment(rawValue: "\(strength)"))
        }
    }

    @Test("the strength is inverted: nothing thrown away is a frame held exactly")
    func theStrengthIsInverted() throws {
        let png = try Self.png()
        for (setting, held) in [(0.0, Float(1)), (0.4, Float(0.6)), (0.9, Float(0.1))] {
            let request = try LTX2RequestMapper.request(
                for: Self.settings(reference: png, strength: setting), descriptor: Self.descriptor)
            let frame = try #require(request.firstFrame)
            #expect(abs(frame.strength - held) < 1e-6, Comment(rawValue: "\(setting)"))
        }
    }

    @Test("the model's own default holds the frame exactly, which is what image-to-video means")
    func theDefaultHoldsTheFrame() throws {
        let request = try LTX2RequestMapper.request(
            for: Self.settings(reference: try Self.png(), strength: Self.descriptor.capabilities.defaultReferenceStrength),
            descriptor: Self.descriptor)
        #expect(try #require(request.firstFrame).strength == 1)
    }

    @Test("a strength outside the model's bounds is clamped before it is inverted")
    func outOfBoundsIsClamped() throws {
        let request = try LTX2RequestMapper.request(
            for: Self.settings(reference: try Self.png(), strength: 1),
            descriptor: Self.descriptor)
        // 1 is not offered; clamped to 0.9 and inverted to 0.1, the least a frame is ever held
        // by. A conditioning strength of 0 would be a picture read and then ignored.
        #expect(abs(try #require(request.firstFrame).strength - 0.1) < 1e-6)
    }

    @Test("something that is not a picture fails before the first step rather than during it")
    func anUnreadablePictureThrows() {
        #expect(throws: (any Error).self) {
            try LTX2RequestMapper.request(
                for: Self.settings(reference: Data("not a picture".utf8), strength: 0),
                descriptor: Self.descriptor)
        }
    }

    @Test("the clip's own settings still survive the trip")
    func theRestOfTheRequestIsUnchanged() throws {
        var settings = Self.settings(reference: nil, strength: 0)
        settings.prompt = "a kite"
        settings.frames = 30
        settings.seed = 42
        let request = try LTX2RequestMapper.request(for: settings, descriptor: Self.descriptor)
        #expect(request.prompt == "a kite")
        // 30 is between two rungs of the 1 + 8k ladder and rounds down to 25.
        #expect(request.frames == 25)
        #expect(request.seed == 42)
        #expect(request.frameRate == 24)
    }
}
