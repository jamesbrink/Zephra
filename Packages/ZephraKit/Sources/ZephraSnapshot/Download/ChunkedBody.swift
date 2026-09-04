import Foundation

/// The body of one transfer, chunk by chunk, telling `ChunkedDownload` as each is taken so a
/// transfer paused for want of room knows when there is room again.
///
/// A chunk counts as taken the moment the writer receives it. The writer holds one chunk at a
/// time and writes it before asking for the next, so what is still buffered is at most one
/// chunk more than the count says, which is what the water marks allow for.
struct ChunkedBody: AsyncSequence, Sendable {
    typealias Element = Data
    typealias Failure = any Error

    let stream: AsyncThrowingStream<Data, any Error>
    let download: ChunkedDownload
    let task: Int

    func makeAsyncIterator() -> Iterator {
        Iterator(inner: stream.makeAsyncIterator(), download: download, task: task)
    }

    struct Iterator: AsyncIteratorProtocol {
        var inner: AsyncThrowingStream<Data, any Error>.AsyncIterator
        let download: ChunkedDownload
        let task: Int

        mutating func next() async throws -> Data? {
            guard let chunk = try await inner.next() else { return nil }
            download.drained(chunk.count, task: task)
            return chunk
        }
    }
}
