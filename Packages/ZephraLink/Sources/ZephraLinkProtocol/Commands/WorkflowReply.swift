import ZephraCore

public enum WorkflowReply: Codable, Hashable, Sendable {
    case history([PromptHistoryEntry])
    case storage([ModelStorageDTO])
}
