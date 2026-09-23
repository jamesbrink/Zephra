import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkClient

/// Whether the phone may tell the Mac to read a model in, or to give it back.
///
/// Gated on the snapshot's own flag rather than the protocol version, which the handshake makes
/// both ends match on exactly. A Mac without the flag is never sent either command: there the
/// phone draws neither control, and the Mac's own widened admission is what lets a plain press
/// of Generate recover from a fault.
@MainActor
@Suite("Loading and unloading the Mac's model from the phone")
struct LinkModelLoadingTests {
    @Test("a Mac that says nothing about it is sent neither command")
    func anolderMacIsNeverAsked() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        world.modelLoading = nil
        try await bed.client.pair(with: bed.pairingCode())
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        try await bed.host.announce(world, kind: .snapshot)
        try await LinkGapRecoveryTests.settle { bed.client.hasFreshSnapshot }

        #expect(!bed.client.supportsModelLoading)
        let before = bed.host.commands.count
        for send in [{ try await bed.client.loadModel("z") }, { try await bed.client.unloadModel() }] {
            do {
                try await send()
                Issue.record("a Mac that never had the command was sent it anyway")
            } catch let error as LinkError {
                #expect(error.code == .unsupported)
            }
        }
        #expect(bed.host.commands.count == before, "nothing left the phone")
    }

    @Test("a Mac that advertises it is sent the command it advertised")
    func anewMacTakesBoth() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        world.modelLoading = true
        try await bed.client.pair(with: bed.pairingCode())
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        try await bed.host.announce(world, kind: .snapshot)
        try await LinkGapRecoveryTests.settle { bed.client.supportsModelLoading }

        try await bed.client.loadModel("flux2-klein-4b-4bit")
        try await bed.client.unloadModel()

        #expect(bed.host.commands.contains(.loadModel("flux2-klein-4b-4bit")))
        #expect(bed.host.commands.contains(.unloadModel))
    }

    @Test("a cached flag is not permission: the command waits for this session's snapshot")
    func acachedFlagIsNotPermission() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        world.modelLoading = true
        bed.client.snapshot = world
        try await bed.client.pair(with: bed.pairingCode())

        #expect(!bed.client.hasFreshSnapshot)
        #expect(!bed.client.supportsModelLoading, "a flag from the last session says nothing")
        do {
            try await bed.client.loadModel("z")
            Issue.record("a cached capability authorized a command")
        } catch let error as LinkError {
            #expect(error.code == .unsupported)
        }
        #expect(bed.host.commands.isEmpty)
    }
}
