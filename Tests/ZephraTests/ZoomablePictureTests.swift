import AppKit
import SwiftUI
import Testing
import ZephraEngine

@testable import Zephra

/// What the View menu's four zoom commands do to a picture on screen, and that a new picture
/// starts again at fit. Hosted in an off-screen window, pressed through the same `PictureZoom`
/// the menu bar reaches through the scene's focused value.
@Suite("Zooming a picture", .serialized)
@MainActor
struct ZoomablePictureTests {
    @Test("Zoom In and Zoom Out walk the ladder; Actual Size and Zoom to Fit land where they say")
    func commandsWalkTheLadder() async throws {
        let window = ZoomTestWindow(picture(key: 1))
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        let zoom = try #require(scroll.zoom)
        let ladder = zoom.scale.ladder
        #expect(!zoom.canFit && !zoom.canZoomOut && zoom.canZoomIn)

        zoom.zoomIn()
        #expect(abs(scroll.magnification - ladder[1]) < 0.001)
        zoom.zoomIn()
        #expect(abs(scroll.magnification - ladder[2]) < 0.001)
        zoom.zoomOut()
        #expect(abs(scroll.magnification - ladder[1]) < 0.001)
        #expect(zoom.canFit)

        zoom.showActualSize()
        #expect(zoom.scale.isActualSize(scroll.magnification))
        #expect(!zoom.canShowActualSize)

        zoom.fit()
        #expect(scroll.isAtFit)
        #expect(zoom.magnification == scroll.magnification)
    }

    @Test("a 1024-pixel picture fitted to 600 points is actual size at 1024 over 600")
    func actualSizeIsPixelsPerPoint() async throws {
        let window = ZoomTestWindow(picture(key: 1))
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        #expect(scroll.documentView?.frame.size == CGSize(width: 600, height: 600))
        #expect(abs((scroll.zoom?.scale.actualSize ?? 0) - 1024.0 / 600) < 0.001)
    }

    @Test("a zoomed picture goes back to fit when another takes its place, and stays zoomed when the same one is drawn again")
    func newKeyResetsToFit() async throws {
        let window = ZoomTestWindow(picture(key: 1))
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        scroll.zoom(to: 4)
        #expect(abs(scroll.magnification - 4) < 0.001)

        window.host.rootView = AnyView(picture(key: 1))
        await window.settle()
        #expect(abs(scroll.magnification - 4) < 0.001, "the same picture kept its zoom")

        window.host.rootView = AnyView(picture(key: 2))
        await window.settle()
        #expect(scroll.isAtFit, "another picture started at fit")
        #expect(scroll.zoom?.canFit == false)
    }

    @Test("a resize keeps the picture fitted")
    func resizeRefits() async throws {
        let window = ZoomTestWindow(picture(key: 1))
        defer { window.close() }
        let scroll = try #require(await window.scrollView())
        window.window.setContentSize(NSSize(width: 500, height: 400))
        window.host.frame.size = NSSize(width: 500, height: 400)
        await window.settle()
        #expect(scroll.documentView?.frame.size == CGSize(width: 400, height: 400))
        #expect(scroll.isAtFit)
    }

    private func picture(key: Int) -> some View {
        let image = PreviewImages.sample()
        let decoded = NSImage(data: image.pngData)!
        return ZoomablePicture(picture: DrawnPicture(decoded, hasAlpha: false), key: key)
    }
}
