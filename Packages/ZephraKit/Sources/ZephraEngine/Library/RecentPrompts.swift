import Foundation

/// The last few things asked for, read off the library rather than kept anywhere.
///
/// The empty canvas offers them as a way back in. Nothing is persisted for it: the library is
/// on disk, its index is there at launch, and every image in it carries its prompt, so the
/// recent prompts are the newest distinct ones in the index. A list kept separately would
/// have to be kept in step with deletions; this one cannot drift.
public enum RecentPrompts {
    /// The newest `limit` distinct prompts among `items`, newest first, leaving out blanks and
    /// the one already in the field.
    ///
    /// `items` is taken in the index's own order, newest first. Two prompts that differ only in
    /// case or surrounding whitespace are the same prompt, and the newest spelling wins.
    public static func from(
        _ items: [LibraryItem],
        excluding current: String,
        limit: Int = 3
    ) -> [String] {
        var seen: Set<String> = [Self.key(current)]
        var prompts: [String] = []
        for item in items {
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, seen.insert(Self.key(prompt)).inserted else { continue }
            prompts.append(prompt)
            if prompts.count == limit { break }
        }
        return prompts
    }

    private static func key(_ prompt: String) -> String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
