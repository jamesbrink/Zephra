import Foundation

extension Duration {
    /// The duration as a plain number of seconds, which is what a benchmark reports.
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
