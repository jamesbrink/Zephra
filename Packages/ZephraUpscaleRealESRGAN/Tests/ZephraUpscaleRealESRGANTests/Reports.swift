import Foundation
import ZephraCore

/// Somewhere for the progress callback to put what it was told. A class rather than a captured
/// `var`, because the callback is escaping.
final class Reports {
    private(set) var all: [UpscaleProgressEvent] = []

    func append(_ event: UpscaleProgressEvent) { all.append(event) }
}
