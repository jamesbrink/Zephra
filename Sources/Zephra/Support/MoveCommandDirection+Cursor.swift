import SwiftUI
import ZephraEngine

extension LibraryCursor.Direction {
    /// The arrow key SwiftUI reported, as the direction `LibraryCursor` moves in; nil for a
    /// move command that is not an arrow. In one place so the library grid and the reference
    /// picker, which both answer `onMoveCommand`, cannot map the keys differently.
    init?(_ command: MoveCommandDirection) {
        switch command {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        @unknown default: return nil
        }
    }
}
