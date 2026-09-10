import Foundation

/// `WanPipeline`'s `prompt_clean`: HTML entities unescaped, twice, and every run of
/// whitespace collapsed to one space with the ends stripped.
///
/// The reference also runs ftfy's `fix_text` first when ftfy is installed, repairing
/// mojibake; that is left out, and a prompt pasted in with broken encoding reaches the
/// tokenizer as typed. The unescape is Python's `html.unescape` for numeric references and
/// for the named entities a prompt is likely to carry, not the full HTML5 table of two
/// thousand names; a name not here stays as it was written, which is what Python does with an
/// unknown one. Whitespace is Python's `\s` on `str`: Unicode `White_Space` plus the four
/// information separators U+001C to U+001F.
public enum WanPromptCleaning {
    /// The prompt as the encoder should see it.
    public static func clean(_ text: String) -> String {
        collapsingWhitespace(unescapingHTML(unescapingHTML(text)))
    }

    /// Whitespace runs to one space, ends stripped.
    static func collapsingWhitespace(_ text: String) -> String {
        var words: [String] = []
        var word = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || (0x1C...0x1F).contains(scalar.value) {
                if !word.isEmpty { words.append(String(word)); word.removeAll() }
            } else {
                word.append(scalar)
            }
        }
        if !word.isEmpty { words.append(String(word)) }
        return words.joined(separator: " ")
    }

    /// `&name;`, `&#NNN;` and `&#xHH;` to their characters, once.
    static func unescapingHTML(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "&", let (replacement, length) = WanHTMLEntity.reference(at: index, in: scalars)
            else {
                result.append(scalars[index])
                index += 1
                continue
            }
            result.append(contentsOf: replacement.unicodeScalars)
            index += length
        }
        return String(result)
    }
}
