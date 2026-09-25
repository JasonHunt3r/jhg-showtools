import SwiftUI
import ShowToolsCore

/// "Replace Image…" (item 8, work order; plan.md, "Replace a slide's
/// image"): a slide's `itemID` points at another file, everything else
/// about it — length, transition, Pan and Zoom, transform, effects —
/// carries over unchanged, since every position in its settings is
/// already a fraction of the image, not pixels. Only pictures replace
/// pictures. One tap picks and closes, the same shape as `LibraryPicker`
/// ("Place Image Here…"), scoped to the show's own collection: unlike
/// Fill Range's picker, there's no Library tab, since the plan calls for
/// "a picker of the collection" alone.
struct ReplaceImagePicker: View {
    let show: Show
    let currentItemID: Int64
    let choose: (Int64) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var items: [MediaItem] {
        guard let cid = show.collectionID, let ids = model.collection(cid)?.itemIDs else { return [] }
        return ids.compactMap { model.itemsByID[$0] }.filter { $0.kind.isPicture }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Replace Image").font(.headline).padding(12)
            Divider()
            if items.isEmpty {
                ContentUnavailableView("Nothing to replace with", systemImage: "photo.on.rectangle.angled")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 12) {
                        ForEach(items) { item in
                            let isCurrent = item.id == currentItemID
                            Button {
                                guard !isCurrent else { return }
                                choose(item.id)
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    ThumbnailView(item: item, url: model.url(for: item))
                                        .frame(width: 110, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 3))
                                    Text(item.fileName).font(.caption).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isCurrent)
                            .help(isCurrent ? "\(item.fileName) (already used here)" : item.fileName)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 460)
    }
}
