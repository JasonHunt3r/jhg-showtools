// Drive the app from the command line, for checks Claude runs by hand.
// Needs Accessibility permission for the app Claude runs in (granted
// 2026-09-21). Read the UI through Accessibility; act with real mouse and
// key events, so the app sees exactly what a person's hands would give it.
//
//   swiftc -O tools/axtool.swift -o /tmp/axtool
//   axtool dump <pid> [depth]            every element: role, label, frame
//   axtool find <pid> <text> [role]      first element whose label contains
//                                        text: its centre and value
//   axtool menu <pid> <menu> <item>...   choose a menu item (by exact title;
//                                        more titles walk into submenus)
//   axtool menustate <pid> <menu> <item> an item's title and whether enabled
//   axtool focused <pid>                 the element that has the keyboard
//   axtool front <pid>                   bring that app forward (do before input)
//   axtool click <x> <y> [right|double|cmd|shift]
//   axtool drag <x1> <y1> <x2> <y2>
//   axtool type <text>
//   axtool key <name> [cmd,shift,opt,ctrl]   return, escape, delete, space,
//                                        tab, left, right, up, down, or a letter
//
// Screen points, top-left origin, as `dump` prints them. click, drag, type
// and key refuse to run unless ShowTools is the frontmost app.
import ApplicationServices
import AppKit

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
func role(_ e: AXUIElement) -> String { attr(e, kAXRoleAttribute) as? String ?? "?" }
func labels(_ e: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute]
        .compactMap { attr(e, $0).map { "\($0)" } }.filter { !$0.isEmpty }
}

func dump(_ e: AXUIElement, _ depth: Int, _ max: Int) {
    let f = frame(e).map { String(format: "(%.0f,%.0f %.0fx%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? ""
    print(String(repeating: "  ", count: depth) + "\(role(e)) \"\(labels(e).first?.prefix(60) ?? "")\" \(f)")
    guard depth < max else { return }
    for k in children(e) { dump(k, depth + 1, max) }
}

func find(_ e: AXUIElement, _ text: String, _ wantRole: String?) -> AXUIElement? {
    if (wantRole == nil || role(e) == wantRole), labels(e).contains(where: { $0.contains(text) }),
       let f = frame(e), f.width > 0 { return e }
    for k in children(e) { if let hit = find(k, text, wantRole) { return hit } }
    return nil
}

/// Exact titles, except the last, which may be a prefix ("Undo" finds
/// "Undo Rename Show").
func menuItem(_ app: AXUIElement, _ path: [String]) -> AXUIElement? {
    guard let bar = attr(app, kAXMenuBarAttribute) else { return nil }
    var here = bar as! AXUIElement
    for (i, title) in path.enumerated() {
        // A menu bar item or menu item holds its items one level down, in an AXMenu.
        let pool = children(here).flatMap { role($0) == "AXMenu" ? children($0) : [$0] }
        let last = i == path.count - 1
        guard let next = pool.first(where: {
            guard let t = attr($0, kAXTitleAttribute) as? String else { return false }
            return t == title || (last && t.hasPrefix(title))
        }) else { return nil }
        here = next
    }
    return here
}

func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left, clicks: Int64 = 1,
          flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
    e?.setIntegerValueField(.mouseEventClickState, value: clicks)
    e?.flags = flags
    e?.post(tap: .cghidEventTap)
    usleep(40_000)
}

let source = CGEventSource(stateID: .privateState)

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
    "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "=": 24, "-": 27,
]

func key(_ name: String, _ mods: String) {
    guard let code = keyCodes[name] else { print("unknown key \(name)"); exit(1) }
    var flags = CGEventFlags()
    for m in mods.split(separator: ",") {
        switch m {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt": flags.insert(.maskAlternate)
        case "ctrl": flags.insert(.maskControl)
        default: break
        }
    }
    // Its own event source, and flags set on every event: posted with the
    // system's combined state, a ⌘ from an earlier key could stick to the
    // next ones and turn typing into shortcuts.
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

func type(_ text: String) {
    for ch in text {
        let units = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            e?.post(tap: .cghidEventTap)
        }
        usleep(8_000)
    }
}

/// Events go to whatever app is in front, not to ShowTools. Every click,
/// drag and key checks first, and refuses if ShowTools isn't frontmost:
/// on 2026-09-21 typed paths landed in Jason's editor when it came forward.
func requireShowToolsInFront() {
    let front = NSWorkspace.shared.frontmostApplication
    guard front?.bundleIdentifier == "com.jhg.showtools" else {
        print("REFUSED: \(front?.localizedName ?? "another app") is in front, not ShowTools")
        exit(2)
    }
}

let a = CommandLine.arguments
guard a.count >= 2 else { print("see the header of axtool.swift"); exit(1) }
if ["click", "drag", "type", "key"].contains(a[1]) { requireShowToolsInFront() }
let app = { AXUIElementCreateApplication(pid_t(a[2])!) }
switch a[1] {
case "dump":
    dump(app(), 0, a.count > 3 ? Int(a[3])! : 12)
case "find":
    guard let e = find(app(), a[3], a.count > 4 ? a[4] : nil), let f = frame(e) else { print("not found"); exit(1) }
    let value = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
    print(String(format: "%.0f %.0f", f.midX, f.midY), role(e), "value=\(value)")
case "menu":
    guard let item = menuItem(app(), Array(a[3...])) else { print("no such menu item"); exit(1) }
    // Walking into a submenu needs it opened first; pressing the leaf chooses it.
    AXUIElementPerformAction(item, kAXPressAction as CFString)
case "menustate":
    guard let item = menuItem(app(), Array(a[3...])) else { print("no such menu item"); exit(1) }
    print(attr(item, kAXTitleAttribute) ?? "", "enabled=\(attr(item, kAXEnabledAttribute) ?? "?" as AnyObject)")
case "front":
    NSRunningApplication(processIdentifier: pid_t(a[2])!)?.activate()
    usleep(400_000)
    print(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")
case "focused":
    guard let e = attr(app(), kAXFocusedUIElementAttribute) else { print("nothing focused"); exit(1) }
    let el = e as! AXUIElement
    print(role(el), labels(el).first ?? "", frame(el).map { "\($0)" } ?? "")
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    let mode = a.count > 4 ? a[4] : ""
    post(.mouseMoved, p)
    if mode == "right" {
        post(.rightMouseDown, p, .right); post(.rightMouseUp, p, .right)
    } else if mode == "cmd" || mode == "shift" {
        let f: CGEventFlags = mode == "cmd" ? .maskCommand : .maskShift
        post(.leftMouseDown, p, flags: f); post(.leftMouseUp, p, flags: f)
    } else {
        post(.leftMouseDown, p); post(.leftMouseUp, p)
        if mode == "double" { post(.leftMouseDown, p, clicks: 2); post(.leftMouseUp, p, clicks: 2) }
    }
case "drag":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!), q = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    post(.mouseMoved, p)
    post(.leftMouseDown, p)
    for i in 1...20 {
        let t = Double(i) / 20
        post(.leftMouseDragged, CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
    }
    usleep(200_000)
    post(.leftMouseUp, q)
case "type":
    type(a[2])
case "key":
    key(a[2], a.count > 3 ? a[3] : "")
default:
    print("unknown command \(a[1])"); exit(1)
}
