import Foundation
import Observation
import ZephraCore
import ZephraSnapshot

/// Model requests survive selection changes. Repository work lives in the injected pool;
/// only the foreground caller borrows a finished result for build/load.
@MainActor @Observable
public final class ModelDownloads {
    public internal(set) var items: [ModelDownload] = []
    @ObservationIgnored let transfers: ModelTransfers
    @ObservationIgnored var requests: [String: DownloadRequest] = [:]
    @ObservationIgnored var retained: [UUID: DownloadRequest] = [:]
    @ObservationIgnored var admissionClosed = false

    public init(transfers: ModelTransfers = ModelTransfers()) { self.transfers = transfers }

    func start(_ model: ModelDescriptor, registry: BackendRegistry, locations: ModelLocations) -> DownloadRequest? {
        guard !admissionClosed else { return nil }
        if let request = requests[model.id], request.model == model, request.locations == locations,
           !request.released, request.stopped == nil { return request }
        let request = DownloadRequest(model, locations)
        requests[model.id] = request
        retained[request.id] = request
        publish(request, .queued)
        request.task = Task {
            do {
                try await transfers.reserve(request.id, model: model, locations: locations)
                try Task.checkCancellation()
                let path = try await ModelResolution().resolve(model, registry: registry, locations: locations,
                    acquisition: TransferAcquisition(id: request.id, pool: transfers)) { event in
                    Task { @MainActor in self.progress(request.id, event) }
                }
                try Task.checkCancellation()
                request.settled = true
                publish(request, .completed)
                await releaseIfUnused(request)
                return path
            } catch {
                request.settled = true
                publish(request, request.stopped ?? (error is CancellationError ? .paused : .failed(error.localizedDescription)))
                await releaseIfUnused(request)
                throw error
            }
        }
        return request
    }

    func acquire(_ model: ModelDescriptor, registry: BackendRegistry, locations: ModelLocations,
                 progress: @escaping @MainActor (DownloadProgressEvent) -> Void) async throws -> AcquiredModel {
        guard let request = start(model, registry: registry, locations: locations), let task = request.task else {
            throw CancellationError()
        }
        request.borrowers += 1
        request.progress = progress
        await transfers.prioritize(request.id)
        if let event = items.first(where: { $0.id == model.id })?.progress { progress(event) }
        do {
            let path = try await TaskReceipt().value(of: task)
            try Task.checkCancellation()
            return AcquiredModel(id: request.id, model: model, locations: locations, directory: path)
        } catch {
            request.progress = nil
            request.borrowers -= 1
            await releaseIfUnused(request)
            throw error
        }
    }

    func release(_ acquired: AcquiredModel) async {
        guard let request = retained[acquired.id] else { return }
        request.progress = nil
        request.borrowers -= 1
        await releaseIfUnused(request)
    }

    /// Whether the request `id` names is still held: unsettled, or settled and borrowed.
    func isRetained(_ id: UUID) -> Bool { retained[id] != nil }

    func releaseIfUnused(_ request: DownloadRequest) async {
        guard request.settled, request.borrowers == 0, !request.released else { return }
        request.released = true
        do { try await transfers.release(request.id, discard: request.discard) }
        catch { publish(request, .failed("Couldn't remove partial files: \(error.localizedDescription)")) }
        retained.removeValue(forKey: request.id)
    }

    func publish(_ request: DownloadRequest, _ status: ModelDownload.Status) {
        guard requests[request.model.id]?.id == request.id else { return }
        if let index = items.firstIndex(where: { $0.id == request.model.id }) { items[index].status = status }
        else { items.append(ModelDownload(id: request.model.id, model: request.model, status: status)) }
    }

    func progress(_ id: UUID, _ event: DownloadProgressEvent) {
        guard let request = retained[id], !request.settled, request.stopped == nil,
              requests[request.model.id]?.id == id,
              let index = items.firstIndex(where: { $0.id == request.model.id }) else { return }
        items[index].status = .downloading
        items[index].progress = event
        request.progress?(event)
    }
}
