import Foundation
import Observation
import ZephraLinkProtocol

@MainActor @Observable
final class RemoteModelStorage {
    var rows: [ModelStorageDTO] = []
    var failure: String?
    var loading = false
    var deleting: ModelStorageDTO?
    private var refreshID = UUID()
    func refresh(_ host: HostConnection) async {
        let ticket = UUID(); refreshID = ticket; loading = true
        do {
            let rows = try await host.client.modelStorage()
            guard ticket == refreshID, !Task.isCancelled else { return }
            self.rows = rows; failure = nil
        } catch {
            guard ticket == refreshID else { return }
            failure = error.localizedDescription
        }
        if ticket == refreshID { loading = false }
    }
    func delete(_ host: HostConnection, item: ModelStorageDTO) async {
        loading = true; failure = nil; deleting = nil
        do { _ = try await host.client.workflow(.delete(id: UUID(), token: item.id)) }
        catch { failure = error.localizedDescription; loading = false; return }
        await refresh(host)
    }
}
