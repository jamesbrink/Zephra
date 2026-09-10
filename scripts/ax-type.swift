// Types into a text field in the running Zephra through the accessibility tree and confirms
// it, without activating the app or moving the mouse: the sibling of ax-press.swift for the
// fields a popover opens on.
//
// usage: swift ax-type.swift "<label>" "<text>"   set the value of the first AXTextField whose
//                                                  AXDescription (its accessibility label) is
//                                                  exactly <label>, then perform AXConfirm,
//                                                  which is what Return does in it
//
// Same requirements as ax-press.swift: Accessibility for the terminal, ZEPHRA_PID to pick a
// copy. Exit status: 0 typed, 1 not found or Zephra not running, 2 usage.
import AppKit
import ApplicationServices

let bundleID = "io.zephra.Zephra"
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    print("usage: ax-type.swift \"<label>\" \"<text>\"")
    exit(2)
}
let wantedPID = ProcessInfo.processInfo.environment["ZEPHRA_PID"].flatMap { pid_t($0) }
let copies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
guard let app = copies.first(where: { wantedPID == nil || $0.processIdentifier == wantedPID }) else {
    print("ax-type: Zephra is not running\(wantedPID.map { " as pid \($0)" } ?? "")")
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

func find(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if text(element, kAXRoleAttribute as String) == kAXTextFieldRole as String,
        text(element, kAXDescriptionAttribute as String) == arguments[0]
    {
        return element
    }
    guard depth < 25 else { return nil }
    for child in children(of: element) {
        if let found = find(child, depth: depth + 1) { return found }
    }
    return nil
}

guard let field = find(application) else {
    print("ax-type: no text field labelled \"\(arguments[0])\"")
    exit(1)
}
let set = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, arguments[1] as CFTypeRef)
let confirmed = AXUIElementPerformAction(field, kAXConfirmAction as CFString)
print("ax-type: set \(set == .success ? "ok" : "\(set.rawValue)"), confirm \(confirmed == .success ? "ok" : "\(confirmed.rawValue)")")
exit(set == .success ? 0 : 1)
