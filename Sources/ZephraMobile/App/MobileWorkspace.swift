import Foundation
import Observation
import UIKit
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraLinkTransport

@MainActor @Observable
final class MobileWorkspace {
    let hosts: HostConnections
    let dispatch: GenerationDispatch
    let draft = PromptDraft()
    let reference = ReferenceIntent()
    let selection = MobileSelection()
    var startupFailure: String?
    init() {
        let catalog = LibraryCatalog()
        if let frozen = MobilePreview.client() {
            hosts = HostConnections(storage: nil, catalog: catalog, makeClient: { _ in frozen })
            MobilePreview.addHosts(to: hosts, first: frozen)
            dispatch = GenerationDispatch(hosts: hosts, root: nil)
            // Two pictures in the well, for the states that photograph the strip.
            MobilePreview.seed(draft)
            return
        }
        do {
            let storage = try PairedHosts()
            let libraryRoot = try CacheDirectories.library()
            try LibraryCacheMigration.quarantine(libraryRoot)
            let submissionRoot = libraryRoot.appending(path: "submissions.json")
            let admission = TransferAdmission()
            let budget = BlobBudget()
            let browser = BonjourBrowser()
            let cadence = RelayCadence(messagesPerSecond: 120, burst: 40)
            hosts = HostConnections(storage: storage, catalog: catalog, makeClient: { host in
                Self.client(storage: storage, host: host, admission: admission, budget: budget, cadence: cadence, browser: browser)
            })
            dispatch = GenerationDispatch(hosts: hosts,
                root: submissionRoot)
        } catch {
            let frozen = MobilePreview.unpairedClient()
            hosts = HostConnections(storage: nil, catalog: catalog, makeClient: { _ in frozen })
            dispatch = GenerationDispatch(hosts: hosts, root: nil)
            startupFailure = "Zephra could not read its saved connections. Unlock this phone and reopen the app."
        }
    }
}
