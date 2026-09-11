import Foundation

/// Base64 in the alphabet a URL accepts, unpadded.
///
/// A QR code's payload rides in a query string, and standard base64's `+`, `/` and `=` all have
/// to be escaped there, which costs three characters each. The URL alphabet costs none, and
/// dropping the padding saves two more.
enum Base64URL {
    /// Those bytes as URL-safe base64, no padding.
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The bytes that text is, or nil when it is not base64 at all.
    static func decode(_ text: String) -> Data? {
        var standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 { standard += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: standard)
    }
}
