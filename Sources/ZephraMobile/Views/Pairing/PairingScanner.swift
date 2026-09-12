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
    /// Whether to hold the camera still: true while a pairing is running, so a second reading
    /// cannot start a second pairing over the first.
    let isPaused: Bool

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

    /// Every SwiftUI update passes through here, and while a pairing runs the client's state
    /// changes several times. Starting the scanner on each one restarted VisionKit's tracking,
    /// which read the code in frame again, which paired again, which tore down the pairing in
    /// flight: a phone at the Mac's screen looped for as long as the code was in view. So the
    /// scanner is started only when it is not already running and not asked to pause, and
    /// `ScanGate` in the coordinator drops the re-reading a restart still produces.
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if isPaused {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    /// The delegate, which exists only to turn the first barcode it sees into a string.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// What to do with that string. Replaced on every update, so the closure never holds a
        /// stale view.
        var onScan: (String) -> Void
        /// Each code once, however many times the camera reports it.
        var gate = ScanGate()

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue, gate.admits(text) else { continue }
                // One code is the whole of this screen's job. The scanner is not stopped here:
                // the view pauses it while the pairing runs, and the gate keeps the same code
                // from pairing twice, so what a running camera can still take is a new code.
                onScan(text)
                return
            }
        }
    }
}
