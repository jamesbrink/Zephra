import UniformTypeIdentifiers

/// The types Zephra declares as its own.
extension UTType {
    /// One image of the library, carried by identity rather than by its bytes.
    ///
    /// Declared in `Info.plist` under `UTExportedTypeDeclarations`, which is what makes the
    /// system recognise it; `UTType(exportedAs:)` is the reading half of that declaration.
    /// It conforms to `public.data` and to nothing more specific on purpose: the payload is a
    /// path, not a picture, and nothing outside Zephra should mistake it for one.
    ///
    /// `nonisolated` because a `TransferRepresentation` is built off the main actor, and this
    /// target's types are main-actor isolated by default.
    nonisolated static let zephraLibraryItem = UTType(exportedAs: "io.zephra.library-item")

    /// One tile of the reference strip, carried by its position while it is dragged to another.
    ///
    /// Declared beside the library item's type and for the same reason, and kept separate from
    /// it so a drop destination can tell a picture arriving from the library from a picture
    /// already in the strip moving along it.
    nonisolated static let zephraReferenceSlot = UTType(exportedAs: "io.zephra.reference-slot")
}
