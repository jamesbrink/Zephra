import AppKit
import Foundation

/// One picture on the pasteboard, in every form a paste might ask for.
///
/// PNG is the bytes as they are, file and record included, and the file's URL is beside it so
/// the Finder pastes the file. TIFF is what the older half of the Mac asks for — a Mail
/// message, a text view, an AppKit `NSImage(pasteboard:)` — and it is promised rather than
/// written: an `NSPasteboardItemDataProvider` is called only when something asks for that
/// type, so ⌘C never pays for a TIFF that is never pasted, which at four megapixels is tens of
/// megabytes of uncompressed pixels.
///
/// Not isolated to the main actor: the pasteboard calls a provider on whichever thread the
/// paste comes in on, and the one thing the provider holds is the immutable PNG.
nonisolated final class PasteboardImage: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let png: Data

    private init(png: Data) {
        self.png = png
    }

    /// An item carrying `png` as PNG, `file` as the file's URL when it has one, and TIFF on
    /// demand.
    static func item(png: Data, file: URL?) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if let file { item.setString(file.absoluteString, forType: .fileURL) }
        item.setData(png, forType: .png)
        item.setDataProvider(PasteboardImage(png: png), forTypes: [.tiff])
        return item
    }

    /// The TIFF, made from the PNG when it is asked for.
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
