import Foundation

/// One HTML character reference, resolved the way Python's `html.unescape` resolves it.
///
/// Numeric references follow the HTML5 rules in full: the C1 range is read as Windows-1252,
/// surrogates and code points past U+10FFFF become U+FFFD, and the noncharacters and controls
/// HTML5 forbids are dropped. Named references cover the entities a prompt is likely to carry;
/// the ones marked legacy resolve without a semicolon too, and, as in Python, one of those
/// found at the front of a longer name resolves and leaves the rest (`&ampfoo` is `&foo`).
enum WanHTMLEntity {
    /// The text an `&` at `index` stands for and how many scalars it spans, or nil when it
    /// is not a reference and stays as written.
    static func reference(at index: Int, in scalars: [Unicode.Scalar]) -> (String, Int)? {
        var end = index + 1
        guard end < scalars.count else { return nil }
        if scalars[end] == "#" {
            end += 1
            let hex = end < scalars.count && (scalars[end] == "x" || scalars[end] == "X")
            if hex { end += 1 }
            let start = end
            while end < scalars.count, scalars[end].properties.isASCIIHexDigit, hex || scalars[end].value < 0x3A {
                end += 1
            }
            guard end > start else { return nil }
            if end < scalars.count, scalars[end] == ";" { end += 1 }
            let digits = String(String.UnicodeScalarView(scalars[start..<(scalars[end - 1] == ";" ? end - 1 : end)]))
            return (numeric(Int(digits, radix: hex ? 16 : 10) ?? 0x110000), end - index)
        }
        let start = end
        while end < scalars.count, end - start < 32, !"\t\n\u{0C} <&#;".unicodeScalars.contains(scalars[end]) {
            end += 1
        }
        guard end > start else { return nil }
        let semicolon = end < scalars.count && scalars[end] == ";"
        let name = String(String.UnicodeScalarView(scalars[start..<end]))
        if semicolon, let entry = named[name] { return (entry.text, end + 1 - index) }
        for length in stride(from: name.count, through: 2, by: -1) {
            let prefix = String(name.prefix(length))
            if let entry = named[prefix], entry.legacy { return (entry.text, start + length - index) }
        }
        return nil
    }

    private static func numeric(_ value: Int) -> String {
        if let replaced = windows1252[value] { return replaced }
        if value == 0 || (0xD800...0xDFFF).contains(value) || value > 0x10FFFF { return "\u{FFFD}" }
        if (0x1...0x8).contains(value) || (0xE...0x1F).contains(value) || (0x7F...0x9F).contains(value)
            || (0xFDD0...0xFDEF).contains(value) || value & 0xFFFE == 0xFFFE || value == 0xB
        {
            return ""
        }
        return Unicode.Scalar(value).map { String($0) } ?? "\u{FFFD}"
    }

    /// The C1 code points HTML5 reads as Windows-1252, with U+000D kept and U+0000 replaced.
    private static let windows1252: [Int: String] = [
        0x00: "\u{FFFD}", 0x0D: "\r", 0x80: "\u{20AC}", 0x81: "\u{81}", 0x82: "\u{201A}", 0x83: "\u{0192}",
        0x84: "\u{201E}", 0x85: "\u{2026}", 0x86: "\u{2020}", 0x87: "\u{2021}", 0x88: "\u{02C6}",
        0x89: "\u{2030}", 0x8A: "\u{0160}", 0x8B: "\u{2039}", 0x8C: "\u{0152}", 0x8D: "\u{8D}",
        0x8E: "\u{017D}", 0x8F: "\u{8F}", 0x90: "\u{90}", 0x91: "\u{2018}", 0x92: "\u{2019}",
        0x93: "\u{201C}", 0x94: "\u{201D}", 0x95: "\u{2022}", 0x96: "\u{2013}", 0x97: "\u{2014}",
        0x98: "\u{02DC}", 0x99: "\u{2122}", 0x9A: "\u{0161}", 0x9B: "\u{203A}", 0x9C: "\u{0153}",
        0x9D: "\u{9D}", 0x9E: "\u{017E}", 0x9F: "\u{0178}",
    ]

    /// Named entities, with whether HTML5 also accepts the name without its semicolon.
    private static let named: [String: (text: String, legacy: Bool)] = [
        "amp": ("&", true), "lt": ("<", true), "gt": (">", true), "quot": ("\"", true),
        "apos": ("'", false), "nbsp": ("\u{A0}", true), "copy": ("\u{A9}", true), "reg": ("\u{AE}", true),
        "trade": ("\u{2122}", false), "deg": ("\u{B0}", true), "times": ("\u{D7}", true),
        "divide": ("\u{F7}", true), "plusmn": ("\u{B1}", true), "middot": ("\u{B7}", true),
        "laquo": ("\u{AB}", true), "raquo": ("\u{BB}", true), "sect": ("\u{A7}", true),
        "para": ("\u{B6}", true), "iexcl": ("\u{A1}", true), "iquest": ("\u{BF}", true),
        "pound": ("\u{A3}", true), "yen": ("\u{A5}", true), "cent": ("\u{A2}", true),
        "euro": ("\u{20AC}", false), "hellip": ("\u{2026}", false), "mdash": ("\u{2014}", false),
        "ndash": ("\u{2013}", false), "lsquo": ("\u{2018}", false), "rsquo": ("\u{2019}", false),
        "ldquo": ("\u{201C}", false), "rdquo": ("\u{201D}", false), "bull": ("\u{2022}", false),
        "frac12": ("\u{BD}", true), "frac14": ("\u{BC}", true), "frac34": ("\u{BE}", true),
        "eacute": ("\u{E9}", true), "egrave": ("\u{E8}", true), "agrave": ("\u{E0}", true),
        "ccedil": ("\u{E7}", true), "ntilde": ("\u{F1}", true), "uuml": ("\u{FC}", true),
        "ouml": ("\u{F6}", true), "auml": ("\u{E4}", true), "szlig": ("\u{DF}", true),
    ]
}
