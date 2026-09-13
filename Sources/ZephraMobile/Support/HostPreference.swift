import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

nonisolated struct HostPreference: Codable, Identifiable, Sendable {
    var host: PairedHost
    var alias: String?
    var enabled = true
    var allowsAuto = true
    var id: HostID { HostID(keys: host.keys) }
    var name: String { alias?.isEmpty == false ? alias! : host.name }
}
