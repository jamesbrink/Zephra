/// User-requested bytes take the next free slot before speculative work.
public enum TransferPriority: Int, Sendable {
    case background = 0
    case visibleThumbnail = 1
    case openedMedia = 2
    case reference = 3
}
