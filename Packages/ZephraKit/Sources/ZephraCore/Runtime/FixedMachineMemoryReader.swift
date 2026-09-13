/// A reader that answers the same thing every time: what a test means by "this Mac has 19 GB
/// free", and what a build with nothing to ask hands in.
public struct FixedMachineMemoryReader: MachineMemoryReader {
    private let reading: MachineMemory?

    public init(reading: MachineMemory?) {
        self.reading = reading
    }

    public func read() -> MachineMemory? { reading }
}
