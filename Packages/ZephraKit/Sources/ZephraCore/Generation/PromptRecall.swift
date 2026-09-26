/// Navigation over newest-first prompts, preserving the draft until it is edited.
public struct PromptRecall: Sendable {
    private var position: Int?
    private var draft = ""
    private var recalled: String?
    public init() {}
    public mutating func reset() { position = nil; recalled = nil }
    public mutating func step(older: Bool, current: String, prompts: [String]) -> String? {
        guard !prompts.isEmpty else { return nil }
        if let recalled, current != recalled { reset() }
        if position == nil {
            guard older else { return nil }
            draft = current
        }
        let next = (position ?? -1) + (older ? 1 : -1)
        guard next < prompts.count else { return nil }
        if next < 0 {
            reset()
            return draft
        }
        position = next
        recalled = prompts[next]
        return recalled
    }
}
