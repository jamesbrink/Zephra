import Foundation

/// The glob a catalog entry filters a repository's files with.
///
/// The rules are the hub's own, which are Python's `fnmatch`: `*` stands for any run of
/// characters, the path separator included, and `?` for exactly one. So `*.json` takes
/// `transformer/config.json` as well as `model_index.json`, and `tokenizer/*` takes everything
/// under that directory however deep. Matching the hub here matters more than matching a shell:
/// a pattern written against `hf download` has to select the same files when Zephra reads it.
///
/// Character classes are deliberately not supported. No catalog entry uses one, and a pattern
/// that quietly means something else than it does to `hf` would be worse than one that matches
/// its brackets literally.
public nonisolated enum FilePattern {
    /// Whether `path` matches `pattern`.
    public static func matches(_ path: String, pattern: String) -> Bool {
        matches(Array(path), Array(pattern))
    }

    /// Whether `path` matches any of `patterns`. An empty list matches everything, the way a
    /// download with nothing to filter by takes the repository whole.
    public static func matchesAny(_ path: String, patterns: [String]) -> Bool {
        patterns.isEmpty || patterns.contains { matches(path, pattern: $0) }
    }

    /// The classic two-cursor glob walk: on a `*`, remember where it was and how far the path
    /// had got, and on a later mismatch come back and let the star swallow one more character.
    /// Linear in the length of the two strings, and no recursion to blow up on a long path.
    private static func matches(_ path: [Character], _ pattern: [Character]) -> Bool {
        var pathIndex = 0
        var patternIndex = 0
        var starIndex: Int?
        var matchIndex = 0
        while pathIndex < path.count {
            if patternIndex < pattern.count,
               pattern[patternIndex] == "?" || pattern[patternIndex] == path[pathIndex]
            {
                pathIndex += 1
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                matchIndex = pathIndex
                patternIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                matchIndex += 1
                pathIndex = matchIndex
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
        return patternIndex == pattern.count
    }
}
