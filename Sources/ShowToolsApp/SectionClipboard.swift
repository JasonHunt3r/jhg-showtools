import AppKit

/// Copy/Paste of one inspector section's settings (`spec/conventions.md` §3,
/// item 6), independent of `SlideClipboard`'s whole-slide copy. Keyed by a
/// short string per section ("transform", "sound") so each section has its
/// own pasteboard slot and copying one doesn't clobber another.
@MainActor
enum SectionClipboard {
    private static func type(_ key: String) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType("com.jhg.showtools.section.\(key)")
    }

    static func copy<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: type(key))
    }

    static func canPaste(key: String) -> Bool {
        NSPasteboard.general.data(forType: type(key)) != nil
    }

    static func paste<T: Decodable>(_ valueType: T.Type, key: String) -> T? {
        guard let data = NSPasteboard.general.data(forType: type(key)) else { return nil }
        return try? JSONDecoder().decode(valueType, from: data)
    }
}
