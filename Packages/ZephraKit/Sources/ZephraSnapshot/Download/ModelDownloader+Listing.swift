import Foundation

extension ModelDownloader {
    /// Every file in `repoID` at `revision`, following the hub's paging to the end.
    ///
    /// `?recursive=true` flattens the tree into one list of paths, which is what the download
    /// wants: the directories are made from the paths as the files are written.
    func listing(of repoID: String, revision: String, on session: URLSession) async throws
        -> [RepositoryFile]
    {
        var next: URL? = host
            .appending(path: "api/models/\(repoID)/tree/\(revision)")
            .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
        var files: [RepositoryFile] = []
        while let page = next {
            try Task.checkCancellation()
            let (data, response) = try await load(page, on: session, repoID: repoID)
            files += try RepositoryListing.files(in: data)
            next = RepositoryListing.nextPage(after: response)
        }
        return files
    }

    /// One page, with the hub's answer read as a status rather than as bytes: no such
    /// repository is a permanent answer, another 4xx is a refusal, and anything else is a
    /// transfer worth trying again.
    func load(_ url: URL, on session: URLSession, repoID: String) async throws -> (
        Data, HTTPURLResponse
    ) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(url))
        } catch let error as CancellationError {
            throw error
        } catch {
            throw ModelDownloadError.interrupted(reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ModelDownloadError.interrupted(
                reason: "The server answered with something that was not HTTP.")
        }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 404: throw ModelDownloadError.repositoryNotFound(repoID: repoID)
        case 400..<500: throw ModelDownloadError.refused(status: http.statusCode, path: repoID)
        default:
            throw ModelDownloadError.interrupted(
                reason: "Hugging Face answered HTTP \(http.statusCode) when asked what \(repoID) holds.")
        }
    }
}
