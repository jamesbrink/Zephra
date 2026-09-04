import Foundation
import Testing
import ZephraSnapshot

@Suite("What the hub says a repository holds")
struct RepositoryListingTests {
    @Test("directories are dropped and an LFS file is counted at its real size")
    func filesAreReadWithTheirRealSizes() throws {
        let json = """
            [
              {"type": "directory", "path": "vae", "size": 0},
              {"type": "file", "path": "model_index.json", "size": 412},
              {"type": "file", "path": "vae/model.safetensors", "size": 135,
               "lfs": {"size": 167335342, "oid": "abc"}}
            ]
            """
        let files = try RepositoryListing.files(in: Data(json.utf8))
        #expect(files.count == 2)
        #expect(files.first == RepositoryFile(path: "model_index.json", bytes: 412))
        #expect(
            files.last == RepositoryFile(path: "vae/model.safetensors", bytes: 167_335_342),
            "the pointer's 135 bytes would make a gigabyte look like nothing")
    }

    @Test("an answer that is not the documented array is refused rather than read as empty")
    func anUnreadableAnswerIsAnError() {
        #expect(throws: ModelDownloadError.unreadableListing) {
            try RepositoryListing.files(in: Data(#"{"error": "not found"}"#.utf8))
        }
    }

    @Test("the next page is the Link header's own URL, cursor and all")
    func nextPageComesFromTheHeader() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://huggingface.co/api/models/a/b/tree/main")!,
                statusCode: 200, httpVersion: nil,
                headerFields: [
                    "Link":
                        "<https://huggingface.co/api/models/a/b/tree/main?cursor=xyz>; rel=\"next\""
                ]))
        #expect(
            RepositoryListing.nextPage(after: response)
                == URL(string: "https://huggingface.co/api/models/a/b/tree/main?cursor=xyz"))
    }

    @Test("a Link header with no next relation ends the listing")
    func aLinkWithoutNextEndsIt() throws {
        let url = URL(string: "https://huggingface.co/api/models/a/b/tree/main")!
        let last = try #require(
            HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Link": "<https://huggingface.co/first>; rel=\"prev\""]))
        #expect(RepositoryListing.nextPage(after: last) == nil)
        let none = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:]))
        #expect(RepositoryListing.nextPage(after: none) == nil)
    }
}
