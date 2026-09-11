import Foundation
import Testing
import ZephraCore
@testable import ZephraLinkProtocol

@Suite("A command reads as English on the wire and comes back the same command")
struct CommandCodingTests {
    static let id = UUID(uuidString: "8B0D5A46-3C2E-4D0B-9F3E-2A1C7E5D4B60")!

    @Test("Every command survives being written and read back")
    func commandsRoundTrip() throws {
        let commands: [Command] = [
            .enqueue(GenerationRequest(
                modelID: "z-image-turbo-4bit", count: 4, settings: LinkFixtures.settings)),
            .cancel,
            .removeFromQueue(Self.id),
            .clearQueue,
            .switchModel("qwen-image-2512-4bit"),
            .setFavourite(names: ["a.png", "b.png"], on: true),
            .setTags(names: ["a.png"], tags: ["dusk", "sea"]),
            .delete(["a.png"]),
            .upscale(name: "a.png", factor: 2),
            .animate(name: "a.png"),
            .fetchThumbnail(name: "a.png", pixels: 512),
            .fetchFile(name: "a.png"),
            .libraryPage(offset: 0, limit: 100),
        ]
        #expect(commands.count == Command.Kind.allCases.count)
        for command in commands {
            #expect(try LinkFixtures.roundTrip(command) == command)
        }
    }

    @Test("A command's JSON is a tagged object whose shape does not move")
    func commandJSONIsStable() throws {
        let json = String(
            decoding: try LinkJSON.encode(Command.setFavourite(names: ["a.png"], on: true)),
            as: UTF8.self)
        #expect(json == #"{"kind":"setFavourite","names":["a.png"],"on":true}"#)
        #expect(
            String(decoding: try LinkJSON.encode(Command.cancel), as: UTF8.self)
                == #"{"kind":"cancel"}"#)
        #expect(
            String(
                decoding: try LinkJSON.encode(Command.libraryPage(offset: 40, limit: 20)),
                as: UTF8.self) == #"{"kind":"libraryPage","limit":20,"offset":40}"#)
    }

    @Test("Every reply survives being written and read back")
    func repliesRoundTrip() throws {
        let replies: [Reply] = [
            .ok,
            .queued(batchID: Self.id),
            .blob(BlobStart(blobID: Self.id, byteCount: 2048, mime: "image/png")),
            .entries(LibraryPage(entries: [LinkFixtures.entry], offset: 0, total: 1)),
            .error(.notPaired),
        ]
        #expect(replies.count == Reply.Kind.allCases.count)
        for reply in replies {
            #expect(try LinkFixtures.roundTrip(reply) == reply)
        }
    }

    @Test("A refusal keeps its code and its sentence")
    func replyErrorJSONIsStable() throws {
        let json = String(
            decoding: try LinkJSON.encode(
                Reply.error(LinkError(code: .busy, reason: "The Mac is busy."))),
            as: UTF8.self)
        #expect(json == #"{"error":{"code":"busy","reason":"The Mac is busy."},"kind":"error"}"#)
    }
}
