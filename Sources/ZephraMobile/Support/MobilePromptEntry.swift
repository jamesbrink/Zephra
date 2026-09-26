import Foundation
import ZephraLinkProtocol

struct MobilePromptEntry: Identifiable, Equatable {
    let id: String
    let hostID: HostID
    let hostName: String
    let prompt: String
    let createdAt: Date
    static func ordered(_ entries: [MobilePromptEntry]) -> [MobilePromptEntry] {
        entries.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            if $0.hostID != $1.hostID { return $0.hostID < $1.hostID }
            return $0.id < $1.id
        }
    }
}
