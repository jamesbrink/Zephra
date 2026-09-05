import AppKit

/// File > Share…: the system's sharing picker over the files the command is about, anchored
/// on the key window's content view since a menu item has no button to hang it from.
///
/// The picker is AppKit's, and the services it lists are the Mac's own — Mail, Messages,
/// AirDrop, whatever else is installed — so nothing here knows a service by name. The inspector
/// and the context menu offer the same list through `ShareLink`, which does have a view to
/// anchor on.
enum SharePicker {
    /// Shows the picker over `files`, or does nothing when there is no window to show it in.
    static func show(files: [URL]) {
        guard !files.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: files)
        let anchor = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}
