import Foundation
import Testing
import ZephraCore
import ZephraEngine
import ZephraTestSupport

@testable import Zephra

@Suite("The bytes an export hands out")
struct ExportDataTests {
    private func image(pngData: Data, fileURL: URL? = nil) -> GeneratedImage {
        GeneratedImage(
            pngData: pngData,
            settings: GenerationSettings(
                prompt: "a quiet street", size: ImageSize(width: 8, height: 8), steps: 4,
                guidance: 0, seed: 42),
            modelID: "z-image-turbo-8bit", duration: .seconds(1), fileURL: fileURL)
    }

    @Test("a picture with a file is exported as that file, not as the bytes in memory")
    func fileWinsOverTheBytesInMemory() throws {
        let scratch = Scratch()
        let onDisk = try scratch.write("what the library annotated since", to: "a.png")
        let inMemory = PreviewImages.gradientPNG(size: ImageSize(width: 8, height: 8))

        let exported = ImageExport.exportData(for: image(pngData: inMemory, fileURL: onDisk))

        #expect(exported == Data("what the library annotated since".utf8))
    }

    @Test("a picture without a file is exported with its generation record embedded")
    func noFileEmbedsTheRecord() {
        let pixels = PreviewImages.gradientPNG(size: ImageSize(width: 8, height: 8))
        let subject = image(pngData: pixels)

        let exported = ImageExport.exportData(for: subject)

        #expect(exported != pixels)
        #expect(GenerationRecord.read(from: exported)?.seed == 42)
        #expect(GenerationRecord.read(from: pixels) == nil)
    }

    @Test("a file that has gone falls back to the bytes in memory rather than to nothing")
    func missingFileFallsBackToTheBytes() {
        let scratch = Scratch()
        let pixels = PreviewImages.gradientPNG(size: ImageSize(width: 8, height: 8))
        let subject = image(pngData: pixels, fileURL: scratch.url("gone.png"))

        let exported = ImageExport.exportData(for: subject)

        #expect(GenerationRecord.read(from: exported)?.seed == 42)
    }
}
