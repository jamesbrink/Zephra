import Darwin
import Foundation
import Testing
import ZephraCore

@testable import Zephra

/// The one reading in the app that asks the kernel rather than a fixture.
///
/// What can be pinned about a live machine is its shape, not its figures: a suite that expected
/// a number would fail on whichever Mac happened to be busy. So this checks that the call
/// answers at all, that the two figures are the ones this Mac has, and that the arithmetic in
/// `MachineMemory` never hands the guard something impossible to compare.
@Suite("what this Mac reports about its own memory")
struct HostMachineMemoryTests {
    @Test("the kernel answers, on every Mac the suite can run on")
    func theReadingIsThere() {
        #expect(HostMachineMemory().read() != nil)
    }

    /// What the kernel says this Mac has, asked the other way round — `sysctl hw.memsize`
    /// rather than the `ProcessInfo` call the reading itself makes, so the test compares two
    /// sources instead of restating one.
    private static func physicalMemoryFromSysctl() -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    @Test("physical memory is the machine's own, and free is a part of it")
    func theFiguresAreTheMachines() throws {
        let reading = try #require(HostMachineMemory().read())
        let sysctlPhysical = try #require(Self.physicalMemoryFromSysctl())
        #expect(reading.physicalBytes == sysctlPhysical)
        #expect(reading.availableBytes >= 0, "a negative reading would admit every load")
        #expect(reading.availableBytes <= reading.physicalBytes)
        #expect(reading.availableFraction >= 0 && reading.availableFraction <= 1)
    }

    @Test("two readings a moment apart are both of the same machine")
    func thePhysicalFigureDoesNotMove() throws {
        let first = try #require(HostMachineMemory().read())
        let second = try #require(HostMachineMemory().read())
        #expect(first.physicalBytes == second.physicalBytes)
    }
}
