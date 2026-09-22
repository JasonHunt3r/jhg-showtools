import Foundation
import ShowToolsCore

/// The libraries BGTools offers: ShowTools' main library and its recent
/// ones (read from ShowTools' own preferences, never written), plus any a
/// setting already names. A test launch (`BGTOOLS_SETTINGS`) offers only
/// those its settings name, so it can't wander into the real library.
struct LibraryChoice: Identifiable, Hashable {
    let path: String
    let name: String
    var id: String { path }
}

enum LibraryChoices {
    static func list(named: [String], environment: [String: String] = ProcessInfo.processInfo.environment) -> [LibraryChoice] {
        var paths: [String] = []
        if environment["BGTOOLS_SETTINGS"] == nil {
            paths.append(LibraryLocation.resolve().path)
            paths += UserDefaults(suiteName: "com.jhg.showtools")?.stringArray(forKey: "recentLibraries") ?? []
        }
        paths += named
        var seen = Set<String>(), out: [LibraryChoice] = []
        for p in paths {
            let key = same(p)
            guard !seen.contains(key),
                  FileManager.default.fileExists(atPath: URL(fileURLWithPath: p).appendingPathComponent("Library.sqlite").path)
            else { continue }
            seen.insert(key)
            let url = URL(fileURLWithPath: p)
            let name = (LibraryLocation.isHidden(url) ? url.deletingPathExtension() : url).lastPathComponent
            out.append(LibraryChoice(path: p, name: name))
        }
        return out
    }

    /// One spelling per folder, for comparing: /tmp and /private/tmp are
    /// the same place, and standardizing alone turns one into the other.
    static func same(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
