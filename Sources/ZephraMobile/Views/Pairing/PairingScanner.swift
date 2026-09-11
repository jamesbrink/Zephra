import SwiftUI
import VisionKit

/// The camera aimed at the code on the Mac's screen.
///
/// VisionKit's own scanner rather than an `AVCaptureSession` of ours: it brings the framing,
/// the highlight and the focus behaviour a person expects, and it is the one piece of this app
/// that is UIKit. Shown only where `isAvailable` says the hardware and the permissions allow
/// it, which is never in the simulator — so `PairingPasteField` is the door that always works.
struct PairingScanner: UIViewControllerRepresentable {
    /// What to do with the text inside the code.
    let onScan: (String) -> Void

    /// Whether this device can scan at all: the hardware supports it and nothing (a missing
    /// camera, a denied permission, a restriction) is in the way right now.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    /// The delegate, which exists only to turn the first barcode it sees into a string.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// What to do with that string. Replaced on every update, so the closure never holds a
        /// stale view.
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue else { continue }
                // One code is the whole of this screen's job: stop looking the moment one is
                // read, so a second code in frame cannot pair to a different Mac.
                scanner.stopScanning()
                onScan(text)
                return
            }
        }
    }
}
