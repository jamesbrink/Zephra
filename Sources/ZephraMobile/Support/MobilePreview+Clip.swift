import AVFoundation
import UIKit

/// The clip the `viewer` state plays, written at launch beside its poster.
///
/// A phone renders nothing and links no media package, so the one MP4 a frozen launch can
/// hold is one written here with `AVAssetWriter`: two seconds of the page's own picture with
/// a bar sweeping across it, so a screenshot shows whether the clip is playing and a pull
/// over it has a frame under the finger. Written synchronously on the way in, since the
/// folder is read the moment the catalog is built and a clip that landed later would be a
/// page that said the picture is not on this phone. Debug launches only, like everything
/// else in `MobilePreview`; a Release build never asks for the folder.
extension MobilePreview {
    /// How many frames the clip holds, and how many a second.
    private static let clipFrames = 24
    private static let clipRate: Int32 = 12

    /// Writes one clip of the numbered page to `url`, or nothing if the writer refuses.
    static func clip(number: Int, size: CGSize, to url: URL) {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let width = Int(size.width), height = Int(size.height)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width, AVVideoHeightKey: height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<clipFrames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            let sweep = CGFloat(frame) / CGFloat(clipFrames)
            guard let buffer = pixelBuffer(
                of: page(number: number, size: size, sweep: sweep), from: adaptor.pixelBufferPool)
            else { break }
            adaptor.append(
                buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: clipRate))
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
    }

    /// One frame's pixels, drawn from the page into a buffer out of the writer's own pool.
    private static func pixelBuffer(of image: UIImage, from pool: CVPixelBufferPool?)
        -> CVPixelBuffer?
    {
        guard let pool, let cgImage = image.cgImage else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(
            cgImage,
            in: CGRect(
                x: 0, y: 0, width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer)))
        return buffer
    }
}
