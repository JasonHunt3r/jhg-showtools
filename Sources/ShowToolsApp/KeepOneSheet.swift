import SwiftUI
import ShowToolsCore

/// Keep One (plan, Phase 3b): a group of look-alikes side by side, one
/// suggested to keep (the largest, then the best rated); click another to
/// keep that instead. The others go the way Delete goes where you are: out
/// of the collection, or to the Trash from the Library. A file a show uses
/// stays. One undo step.
struct KeepOneSheet: View {
    let group: [MediaItem]
    /// Nil in the Library.
    let collectionID: Int64?
    let undoManager: UndoManager?
    let done: (_ removed: [Int64]) -> Void
    @Environment(AppModel.self) private var model
    @State private var keeperID: Int64?

    private var keeper: MediaItem? { group.first { $0.id == keeperID } ?? KeepOne.suggestedKeeper(group) }
    private var used: Set<Int64> { Set(group.map(\.id).filter { !model.showsUsing([$0]).isEmpty }) }

    private var plan: KeepOne.Plan? {
        keeper.map { KeepOne.plan(keeper: $0, group: group, used: used, trashing: collectionID == nil) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keep One").font(.headline)
            Text("Click the one to keep. The others "
                 + (collectionID == nil ? "go to the Trash, and the one you keep takes their tags and best rating."
                                        : "leave this collection; they stay in the library."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group) { card($0) }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Cancel") { done([]) }.keyboardShortcut(.cancelAction)
                Button("Keep One") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan?.remove.isEmpty ?? true)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: min(CGFloat(group.count) * 232 + 40, 1000), maxWidth: 1000)
        .onAppear { keeperID = KeepOne.suggestedKeeper(group)?.id }
    }

    private func card(_ item: MediaItem) -> some View {
        let isKeeper = item.id == keeper?.id
        let shows = model.showsUsing([item.id]).count
        return Button { keeperID = item.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                ThumbnailView(item: item, url: model.url(for: item))
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 160)
                    .overlay(alignment: .topLeading) {
                        Text(isKeeper ? "Keep" : shows > 0 ? "Stays" : collectionID == nil ? "To Trash" : "Leaves")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(isKeeper ? Color.accentColor : Color.black.opacity(0.6)))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                    .opacity(isKeeper || shows > 0 ? 1 : 0.55)
                Text(item.fileName).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text("\(item.pixelWidth) × \(item.pixelHeight) · \(Self.size(of: item, model)) · \((item.fileName as NSString).pathExtension.uppercased())")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text("Added \(item.ingestedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if item.rating > 0 {
                        Text(String(repeating: "★", count: item.rating)).font(.caption).foregroundStyle(.yellow)
                    }
                    if shows > 0 {
                        Text("Used in \(shows == 1 ? "1 show" : "\(shows) shows")").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(6)
            .frame(width: 232, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isKeeper ? Color.accentColor : .clear, lineWidth: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isKeeper ? "Keeping" : "Keep") \(item.fileName)")
    }

    private var summary: String {
        guard let plan, let keeper else { return "" }
        let n = plan.remove.count, kept = plan.keptBecauseUsed.count
        var parts = ["Keeps \(keeper.fileName)."]
        if n > 0 {
            parts.append("\(n) \(collectionID == nil ? (n == 1 ? "goes to the Trash" : "go to the Trash") : (n == 1 ? "leaves the collection" : "leave the collection")).")
        }
        if kept > 0 { parts.append("\(kept) \(kept == 1 ? "stays" : "stay"): used in a show.") }
        return parts.joined(separator: " ")
    }

    private func apply() {
        guard let keeper else { return }
        let plan = model.keepOne(keeper, of: group, collectionID: collectionID, undo: undoManager)
        done(plan.remove)
    }

    private static func size(of item: MediaItem, _ model: AppModel) -> String {
        guard let url = model.url(for: item),
              let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
