import SwiftUI
import ShowToolsCore

/// Pick several files at once, for an empty collection's "Add from
/// Library…" and an empty show's "Add from Collection…" (audit H2). The
/// same shape as `LibraryPicker` ("Place Image Here…"), but multi-select
/// with an Add button instead of choosing one and closing immediately.
struct MultiItemPicker: View {
    let title: String
    let items: [MediaItem]
    let add: (Set<Int64>) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.headline).padding(12)
            Divider()
            if items.isEmpty {
                ContentUnavailableView("Nothing to add", systemImage: "photo.on.rectangle.angled")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 12) {
                        ForEach(items) { item in
                            let isPicked = picked.contains(item.id)
                            Button {
                                if isPicked { picked.remove(item.id) } else { picked.insert(item.id) }
                            } label: {
                                VStack(spacing: 4) {
                                    ThumbnailView(item: item, url: model.url(for: item))
                                        .frame(width: 110, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(isPicked ? Color.accentColor : .clear, lineWidth: 3))
                                    Text(item.fileName).font(.caption).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(item.fileName)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            HStack {
                if !picked.isEmpty {
                    Text("\(picked.count) selected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add(picked); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 560, height: 460)
    }
}
