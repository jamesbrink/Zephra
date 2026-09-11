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
