// Phase 5 test program, part 5: does an ad-hoc-signed app launch at login?
// Two copies of this app, told apart by bundle id, try the two ways:
//
//   com.jhg.loginprobe.sm  registers itself with SMAppService.mainApp
//                          (`--register` / `--unregister` / `--status`)
//   com.jhg.loginprobe.la  is started by ~/Library/LaunchAgents/
//                          com.jhg.loginprobe.la.plist (RunAtLoad)
//
// Every launch appends a line to ~/Library/Logs/BGLoginProbe.log: which
// copy, its arguments, its parent process, and seconds since the Mac
// booted and since this user logged in. Then it quits after a minute.
// Nothing appears on screen (no Dock icon, no window).
import AppKit
import ServiceManagement

let id = Bundle.main.bundleIdentifier ?? "?"
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BGLoginProbe.log")

func log(_ s: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) [\(id)] \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? Data(line.utf8).write(to: logURL) }
    print(line, terminator: "")
}

func secondsSinceBoot() -> Int {
    var tv = timeval(); var size = MemoryLayout<timeval>.size
    sysctlbyname("kern.boottime", &tv, &size, nil, 0)
    return Int(Date().timeIntervalSince1970) - tv.tv_sec
}

func secondsSinceLogin() -> String {
    // The loginwindow session's start: the console user's login time.
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/last")
    p.arguments = ["-1", NSUserName(), "console"]
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.split(separator: "\n").first.map(String.init) ?? "?"
}

func status(_ s: SMAppService.Status) -> String {
    switch s {
    case .notRegistered: "notRegistered"
    case .enabled: "enabled"
    case .requiresApproval: "requiresApproval"
    case .notFound: "notFound"
    @unknown default: "unknown(\(s.rawValue))"
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let service = SMAppService.mainApp
if args.contains("--register") {
    do { try service.register(); log("register ok, status \(status(service.status))") }
    catch { log("register FAILED: \(error) — status \(status(service.status))") }
    exit(0)
}
if args.contains("--unregister") {
    do { try service.unregister(); log("unregister ok, status \(status(service.status))") }
    catch { log("unregister FAILED: \(error)") }
    exit(0)
}
if args.contains("--status") { log("status \(status(service.status))"); exit(0) }

let parent = getppid()
let parentName = (try? String(contentsOfFile: "/proc/\(parent)/comm", encoding: .utf8))
    ?? NSRunningApplication(processIdentifier: parent)?.localizedName ?? "pid \(parent)"
log("LAUNCHED args \(args) parent \(parentName) · \(secondsSinceBoot()) s after boot · last login: \(secondsSinceLogin())")
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { exit(0) }
app.run()
