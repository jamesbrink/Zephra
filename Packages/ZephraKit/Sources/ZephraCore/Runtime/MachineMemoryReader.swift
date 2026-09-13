/// Whatever can tell this layer how much memory the Mac has free.
///
/// Injected rather than read here for the reason every other machine fact is: `ZephraCore` and
/// `ZephraEngine` must answer the same way under test as they do on a Mac, and a guard that
/// consults the real kernel is a guard whose refusals depend on what else is running while the
/// suite runs. The app injects `HostMachineMemory`; a suite injects a fixed reading.
public protocol MachineMemoryReader: Sendable {
    /// The machine's memory right now, or nil where it cannot be read — a build with no host
    /// to ask, or a call the kernel refused. Nil is "do not know", never "nothing free".
    func read() -> MachineMemory?
}
