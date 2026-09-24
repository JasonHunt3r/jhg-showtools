import SwiftUI
import UniformTypeIdentifiers
import ShowToolsCore
import ShowToolsPlayback

/// Library files dragged within the app, from the Collection Browser: a
/// list of their ids, under ShowTools' own type (declared in Info.plist).
/// On the main actor, where the drops arrive.
@MainActor
enum ItemDrag {
    static let type = UTType(exportedAs: "com.jhg.showtools.items")

    static func provider(_ ids: [Int64]) -> NSItemProvider {
        let p = NSItemProvider()
        let data = (try? JSONEncoder().encode(ids)) ?? Data()
        p.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return p
    }

    /// The ids if the drop is our own drag; nil if it's from outside.
    static func ids(from providers: [NSItemProvider]) async -> [Int64]? {
        let ours = providers.filter { $0.hasItemConformingToTypeIdentifier(type.identifier) }
        guard !ours.isEmpty else { return nil }
        var out: [Int64] = []
        for p in ours {
            let data: Data? = await withCheckedContinuation { c in
                _ = p.loadDataRepresentation(forTypeIdentifier: type.identifier) { d, _ in c.resume(returning: d) }
            }
            if let data, let ids = try? JSONDecoder().decode([Int64].self, from: data) { out += ids }
        }
        return out
    }

    /// What a drop onto a show accepts: our own drags, and files from
    /// Finder or Photos.
    static let accepted: [UTType] = [type] + droppableTypes
}

/// A group dragged within the app, from the Library pane: its own id, under
/// ShowTools' own type (declared in Info.plist). Carries one group at a
/// time — the pane's rows aren't multi-selectable the way the grid's are.
@MainActor
enum GroupDrag {
    static let type = UTType(exportedAs: "com.jhg.showtools.group")

    static func provider(_ id: Int64) -> NSItemProvider {
        let p = NSItemProvider()
        let data = (try? JSONEncoder().encode(id)) ?? Data()
        p.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return p
    }

    /// The id if the drop is a group dragged from the Library pane; nil
    /// otherwise (a file drag, or nothing of ours).
    static func id(from providers: [NSItemProvider]) async -> Int64? {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) })
        else { return nil }
        let data: Data? = await withCheckedContinuation { c in
            _ = p.loadDataRepresentation(forTypeIdentifier: type.identifier) { d, _ in c.resume(returning: d) }
        }
        return data.flatMap { try? JSONDecoder().decode(Int64.self, from: $0) }
    }
}

/// A group dragged onto a collection it doesn't belong to: dragging can't
/// move the group there (a group's `collection_id` never changes — plan,
/// "Groups inside collections"), so instead this adds the group's own files
/// to that collection, and says so before doing it. Same suppression
/// convention as `CollectionAddNotice`.
@MainActor
enum GroupToCollectionNotice {
    static let autoAddKey = "autoAddGroupToCollection"

    /// True to go ahead and add them.
    static func confirm(groupName: String, count: Int, collection: String) -> Bool {
        if UserDefaults.standard.bool(forKey: autoAddKey) { return true }
        let alert = NSAlert()
        alert.messageText = "Add “\(groupName)”'s \(count) file\(count == 1 ? "" : "s") to “\(collection)”?"
        alert.informativeText = "“\(groupName)” stays where it is. This only adds the images in this group to “\(collection)” as well."
        alert.addButton(withTitle: "Add to Collection")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Always add without asking"
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: autoAddKey)
        }
        return ok
    }
}

/// A file arriving in a show whose collection doesn't have it (plan, 2b).
/// The question, with the standard suppression checkbox labelled "Always
/// add without asking" (only meaningful with Add, so Cancel can't turn into
/// a silent refusal). Ticking it switches on the preference, which Settings
/// can switch off again.
@MainActor
enum CollectionAddNotice {
    static let autoAddKey = "autoAddToCollection"

    /// True to go ahead and add them.
    static func confirm(count: Int, firstName: String, collection: String) -> Bool {
        if UserDefaults.standard.bool(forKey: autoAddKey) { return true }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "“\(firstName)” isn't in the collection “\(collection)”. Add it?"
                                       : "\(count) files aren't in the collection “\(collection)”. Add them?"
        alert.informativeText = "A show uses files from its collection. Adding puts them in “\(collection)” as well; they stay in any other collection too."
        alert.addButton(withTitle: count == 1 ? "Add to Collection" : "Add Them to Collection")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Always add without asking"
        let ok = alert.runModal() == .alertFirstButtonReturn
        if ok, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: autoAddKey)
        }
        return ok
    }
}
