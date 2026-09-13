// Presses a control in the running Zephra through the accessibility tree, without activating
// the app or moving the mouse, so a person can keep working while an agent drives the window.
//
// usage: swift ax-press.swift "<title>" [role]     press the first control whose AXTitle or
//                                                  AXDescription is exactly <title>, or, for a
//                                                  SwiftUI Form control with neither (a Toggle's
//                                                  title lives in a sibling AXStaticText), whose
//                                                  linked label matches through AXTitleUIElement
//                                                  or AXServesAsTitleForUIElements; role
//                                                  ("AXButton", "AXRadioButton", ...) narrows it
//        swift ax-press.swift --dump [depth]       print the tree, for finding those titles
//        swift ax-press.swift --resize W H         set the main window's size, in points
//        swift ax-press.swift --move X Y           set its top-left corner, in screen points
//        swift ax-press.swift --reveal "<title>"   scroll the named control into view
//
// The three window commands exist for `make screenshot`, which photographs the window by its
// id: a window has to be at the size a screenshot is meant to show, and a card below the fold
// has to be scrolled to, and neither may cost the person at the keyboard their focus. AX sets
// size and position on a background app's window with no activation and no mouse.
//
// The terminal running this needs Accessibility in System Settings > Privacy & Security.
// With two Zephras up — a person's, and a `ZEPHRA_PREVIEW_STATE` launch beside it — set
// ZEPHRA_PID to the one to drive; otherwise the first registered copy is taken.
// Menu items count as controls: `ax-press.swift "About Zephra" AXMenuItem` runs the item
// without opening the menu.
// Exit status: 0 pressed, 1 not found or Zephra not running, 2 usage.
import AppKit
import ApplicationServices

let bundleID = "io.zephra.Zephra"
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("usage: ax-press.swift \"<title>\" [role] | --dump [depth]")
    exit(2)
}
let wantedPID = ProcessInfo.processInfo.environment["ZEPHRA_PID"].flatMap { pid_t($0) }
let copies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
guard let app = copies.first(where: { wantedPID == nil || $0.processIdentifier == wantedPID }) else {
    print("ax-press: Zephra is not running\(wantedPID.map { " as pid \($0)" } ?? "")")
    exit(1)
}
let application = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func text(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String) ?? ""
}

func children(of element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func linkedElements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    (attribute(element, name) as? [AXUIElement]) ?? []
}

/// A single AXUIElement-valued attribute, checked by CFTypeID rather than a conditional
/// downcast, which Swift refuses for a CFType (it always "succeeds", crashing later instead).
func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
}

/// The label text a Toggle or static field borrows through `AXTitleUIElement`, when the
/// control carries no AXTitle or AXDescription of its own.
func titleUIElementText(_ element: AXUIElement) -> String? {
    guard let label = elementAttribute(element, kAXTitleUIElementAttribute as String) else { return nil }
    let title = text(label, kAXTitleAttribute as String)
    if !title.isEmpty { return title }
    let value = text(label, kAXValueAttribute as String)
    return value.isEmpty ? nil : value
}

/// The value of a static text elsewhere in the tree that names `element` through
/// `AXServesAsTitleForUIElements` — the other half of the same SwiftUI Form link, read from
/// the label's side when the control has no `AXTitleUIElement` pointing back.
func servesAsTitleText(for element: AXUIElement, in root: AXUIElement) -> String? {
    var found: String?
    walk(root, maxDepth: 25) { candidate, _ in
        guard text(candidate, kAXRoleAttribute as String) == "AXStaticText" else { return false }
        let value = text(candidate, kAXValueAttribute as String)
        guard !value.isEmpty else { return false }
        guard linkedElements(candidate, kAXServesAsTitleForUIElementsAttribute as String)
            .contains(where: { CFEqual($0, element) }) else { return false }
        found = value
        return true
    }
    return found
}

/// Either half of the linked-label pair, searching the reverse direction only when the
/// control has neither its own title nor a forward `AXTitleUIElement` — the search is a tree
/// walk of its own, so it is worth paying only for a control that actually needs it.
func linkedLabel(for element: AXUIElement, title: String, description: String, root: AXUIElement) -> String? {
    if let forward = titleUIElementText(element) { return forward }
    guard title.isEmpty, description.isEmpty else { return nil }
    return servesAsTitleText(for: element, in: root)
}

/// Walks the tree depth first, stopping at the first element `visit` accepts.
@discardableResult
func walk(_ element: AXUIElement, depth: Int = 0, maxDepth: Int, visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(element, depth) { return true }
    guard depth < maxDepth else { return false }
    for child in children(of: element) where walk(child, depth: depth + 1, maxDepth: maxDepth, visit: visit) {
        return true
    }
    return false
}

/// The app's main window, which is the one a screenshot takes.
func mainWindow() -> AXUIElement? {
    if let main = elementAttribute(application, kAXMainWindowAttribute as String) { return main }
    return (attribute(application, kAXWindowsAttribute as String) as? [AXUIElement])?.first
}

/// Writes one geometry attribute on `window` and says whether the window actually took it: a
/// tiled or full-screen window is resized by the window manager rather than by its own frame,
/// so a write that returns success can still leave the window where it was.
func setGeometry(
    _ window: AXUIElement, _ name: String, _ value: CGPoint, size: CGSize?, label: String
) -> Bool {
    var written = size.map { AXValueCreate(.cgSize, withUnsafePointer(to: $0) { $0 }) }
        ?? AXValueCreate(.cgPoint, withUnsafePointer(to: value) { $0 })
    guard let axValue = written else { return false }
    written = axValue
    let result = AXUIElementSetAttributeValue(window, name as CFString, axValue)
    guard result == .success else {
        print("ax-press: \(label) refused (error \(result.rawValue))")
        return false
    }
    return true
}

/// What the window reports now, for saying whether a write landed.
func windowFrame(_ window: AXUIElement) -> (origin: CGPoint, size: CGSize) {
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(window, kAXPositionAttribute as String),
        CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID()
    {
        AXValueGetValue((value as! AXValue), .cgPoint, &origin)
    }
    if let value = attribute(window, kAXSizeAttribute as String),
        CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID()
    {
        AXValueGetValue((value as! AXValue), .cgSize, &size)
    }
    return (origin, size)
}

if command == "--resize" || command == "--move" {
    guard arguments.count > 2, let first = Double(arguments[1]), let second = Double(arguments[2])
    else {
        print("usage: ax-press.swift \(command) <x|width> <y|height>")
        exit(2)
    }
    guard let window = mainWindow() else {
        print("ax-press: Zephra has no window")
        exit(1)
    }
    let isResize = command == "--resize"
    let ok = setGeometry(
        window,
        isResize ? kAXSizeAttribute as String : kAXPositionAttribute as String,
        CGPoint(x: first, y: second),
        size: isResize ? CGSize(width: first, height: second) : nil,
        label: isResize ? "resize" : "move")
    let frame = windowFrame(window)
    print(
        "ax-press: window is \(Int(frame.size.width))x\(Int(frame.size.height)) "
            + "at \(Int(frame.origin.x)),\(Int(frame.origin.y))")
    // A window manager that tiles or zooms the window keeps its own frame, and the write is
    // then accepted and ignored; saying so is the difference between "resized" and "asked".
    // A window smaller than its own floor is clamped too, and an AX size counts the title bar
    // — a content floor of 880x560 reads back as 880x592 — so a difference is reported rather
    // than treated as a failure, and only a window that did not move at all is one.
    if isResize, Int(frame.size.width) != Int(first) || Int(frame.size.height) != Int(second) {
        print(
            "ax-press: the window settled at its own size — tiled or zoomed, at its minimum, "
                + "or an AX height that counts the title bar")
    }
    exit(ok ? 0 : 1)
}

if command == "--reveal" {
    guard arguments.count > 1 else {
        print("usage: ax-press.swift --reveal \"<title>\"")
        exit(2)
    }
    let wanted = arguments[1]
    let revealed = walk(application, maxDepth: 25) { element, _ in
        let title = text(element, kAXTitleAttribute as String)
        let description = text(element, kAXDescriptionAttribute as String)
        guard title == wanted || description == wanted || description.hasPrefix(wanted)
        else { return false }
        let result = AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
        print("ax-press: revealed \"\(wanted)\" (\(result == .success ? "ok" : "error \(result.rawValue)"))")
        return result == .success
    }
    exit(revealed ? 0 : 1)
}

if command == "--dump" {
    let maxDepth = arguments.count > 1 ? Int(arguments[1]) ?? 12 : 12
    walk(application, maxDepth: maxDepth) { element, depth in
        let role = text(element, kAXRoleAttribute as String)
        let title = text(element, kAXTitleAttribute as String)
        let description = text(element, kAXDescriptionAttribute as String)
        let value = attribute(element, kAXValueAttribute as String).map { "\($0)".prefix(40) } ?? ""
        let linked = linkedLabel(for: element, title: title, description: description, root: application)
        if !title.isEmpty || !description.isEmpty || linked != nil || role.contains("Button") || role.contains("Window") {
            let indent = String(repeating: "  ", count: depth)
            let linkedText = linked.map { " linked=\"\($0)\"" } ?? ""
            print("\(indent)\(role) title=\"\(title)\" desc=\"\(description)\" value=\"\(value)\"\(linkedText)")
        }
        return false
    }
    exit(0)
}

let wanted = command
let role = arguments.count > 1 ? arguments[1] : nil
let pressed = walk(application, maxDepth: 25) { element, _ in
    let elementRole = text(element, kAXRoleAttribute as String)
    if let role, elementRole != role { return false }
    let title = text(element, kAXTitleAttribute as String)
    let description = text(element, kAXDescriptionAttribute as String)
    guard title == wanted || description == wanted
        || linkedLabel(for: element, title: title, description: description, root: application) == wanted
    else { return false }
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    print("ax-press: pressed \(elementRole) \"\(wanted)\" (\(result == .success ? "ok" : "error \(result.rawValue)"))")
    return true
}
if !pressed {
    print("ax-press: no control titled \"\(wanted)\"\(role.map { " with role \($0)" } ?? "")")
    exit(1)
}
