import Testing

@testable import ZephraMobile

@Suite("Reading a pairing code once")
struct ScanGateTests {
    @Test("the first reading of a code is handed on")
    func firstReading() {
        var gate = ScanGate()
        let first = gate.admits("zephra://pair?a")
        #expect(first)
    }

    @Test("the same code read again is not handed on again")
    func sameCodeAgain() {
        var gate = ScanGate()
        let readings = (0..<3).map { _ in gate.admits("zephra://pair?a") }
        #expect(readings == [true, false, false])
    }

    @Test("a different code is handed on, and the one before it is then new again")
    func newCode() {
        var gate = ScanGate()
        let readings = ["a", "b", "b", "a"].map { gate.admits("zephra://pair?\($0)") }
        #expect(readings == [true, true, false, true])
    }
}
