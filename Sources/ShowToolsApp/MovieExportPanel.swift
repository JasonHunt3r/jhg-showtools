import SwiftUI
import AppKit
import ShowToolsCore
import ShowToolsPlayback

// Video export (plan, `spec/video-export.md`). E4b: File ▸ Export Movie…
//
// A Save panel with the options in its accessory view, the way Export
// Show… does it: the size on one row, the rate and format on the next,
// over a note that only speaks when it has something to say (a letterbox,
// a show with no music). Laid out with Jason, 2026-09-22.

/// A movie export's progress, then its result, for `MovieExportBanner`.
struct MovieExportStatus {
    var showName: String
    var fraction: Double = 0
    var finished = false
    var file: URL?
    var summary = ""
    /// Set by the Cancel button and read by the export thread.
    var cancelled = Cancelled()

    /// A box the writing thread can read without touching the model.
    final class Cancelled: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }
}

/// The accessory view's state, kept in one place so the note can react to
/// every popup.
@MainActor
final class MovieExportOptions {
    var settings: MovieExportSettings
    let showSize: CGSize
    let showAspect: CGFloat
    let songs: Int
    var onChange: (() -> Void)?

    init(showSize: CGSize, songs: Int) {
        let even = MovieExportSettings.even(showSize)
        self.showSize = even
        self.showAspect = even.height > 0 ? even.width / even.height : 16.0 / 9.0
        self.songs = songs
        self.settings = MovieExportSettings(size: even)
    }

    /// "Match the show" first, then the standard sizes.
    var sizes: [MovieSizePreset] { [MovieSizePreset.show(showSize)] + MovieSizePreset.standard }

    func title(for preset: MovieSizePreset) -> String {
        "\(preset.name) — \(Int(preset.size.width))×\(Int(preset.size.height))"
    }

    /// The line under the popups. Empty when there is nothing to warn about.
    var note: String {
        var parts: [String] = []
        let plan = settings.plan(showAspect: showAspect)
        if plan.isLetterboxed {
            let bars = plan.picture.width < plan.canvas.width ? "down the sides" : "above and below"
            parts.append("The show is a different shape, so it gets black bars \(bars) "
                         + "(\(Int(plan.picture.width))×\(Int(plan.picture.height)) inside the frame). "
                         + "Nothing is cut off.")
        }
        if songs == 0 {
            parts.append("The show has no music, so the movie is silent.")
        }
        return parts.joined(separator: " ")
    }
}

/// File ▸ Export Movie…: the Save panel, its options, and the export.
@MainActor
func runMovieExportPanel(_ model: AppModel, showID: Int64) {
    guard let lib = model.library, let show = model.show(showID) else { return }
    let items = model.itemsByID
    let timeline = ShowTimeline(show: show, items: items)
    guard timeline.duration > 0 else {
        exportAlert("“\(show.name)” has nothing to export.", "Add a slide to the show first.")
        return
    }

    let songs = MovieSoundTrack.songs(of: show, items: items) { lib.url(for: $0) }
    let options = MovieExportOptions(showSize: outputPixelSize, songs: songs.count)

    let panel = NSSavePanel()
    panel.prompt = "Export"
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = movieFileName(show.name, ext: options.settings.codec.fileExtension)
    panel.allowedContentTypes = [options.settings.codec.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]

    let accessory = MovieExportAccessory(options: options) { [weak panel] in
        // The name must follow the format: a ProRes movie is never .mp4.
        guard let panel else { return }
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.allowedContentTypes = [options.settings.codec.container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.nameFieldStringValue = "\(base).\(options.settings.codec.fileExtension)"
    }
    panel.accessoryView = accessory

    guard panel.runModal() == .OK, let url = panel.url else { return }
    model.exportMovie(timeline: timeline, songs: songs, to: url,
                      settings: options.settings, showAspect: options.showAspect,
                      showName: show.name, lib: lib)
}

/// A show's name as a file name, without the characters a file can't hold.
func movieFileName(_ showName: String, ext: String) -> String {
    let cleaned = showName
        .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
        .joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(cleaned.isEmpty ? "Show" : cleaned).\(ext)"
}

// MARK: - The accessory view

/// Size on one row, frame rate and format on the next, with the note beneath.
@MainActor
final class MovieExportAccessory: NSView {
    private let options: MovieExportOptions
    private let onFormatChange: () -> Void
    private let note = NSTextField(wrappingLabelWithString: "")
    private let warning = NSImageView()

    init(options: MovieExportOptions, onFormatChange: @escaping () -> Void) {
        self.options = options
        self.onFormatChange = onFormatChange
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 124))

        let size = popup(options.sizes.map { options.title(for: $0) }, #selector(sizeChanged))
        let rate = popup(MovieFrameRate.allCases.map(\.name), #selector(rateChanged))
        rate.selectItem(at: MovieFrameRate.allCases.firstIndex(of: options.settings.frameRate) ?? 1)
        let format = popup(MovieCodec.allCases.map(\.menuTitle), #selector(formatChanged))

        // Size on its own row, then rate and format beneath it (Jason,
        // 2026-09-22): the size is the choice that changes what the movie
        // looks like, and it carries the longest titles.
        let sizeRow = NSStackView(views: [label("Size"), size])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 6
        sizeRow.alignment = .firstBaseline

        let formatRow = NSStackView(views: [label("Rate"), rate, label("Format"), format])
        formatRow.orientation = .horizontal
        formatRow.spacing = 6
        formatRow.alignment = .firstBaseline

        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.preferredMaxLayoutWidth = 470
        warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        warning.contentTintColor = .systemOrange

        let noteRow = NSStackView(views: [warning, note])
        noteRow.orientation = .horizontal
        noteRow.spacing = 6
        noteRow.alignment = .top

        let stack = NSStackView(views: [sizeRow, formatRow, noteRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("no coder") }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func popup(_ titles: [String], _ action: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: titles)
        p.target = self
        p.action = action
        // Natural width: each popup is as wide as its longest title.
        p.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return p
    }

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        options.settings.setSize(options.sizes[sender.indexOfSelectedItem].size)
        refresh()
    }

    @objc private func rateChanged(_ sender: NSPopUpButton) {
        options.settings.frameRate = MovieFrameRate.allCases[sender.indexOfSelectedItem]
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        options.settings.codec = MovieCodec.allCases[sender.indexOfSelectedItem]
        onFormatChange()
        refresh()
    }

    /// The note appears only when it has something to say.
    private func refresh() {
        let text = options.note
        note.stringValue = text
        note.isHidden = text.isEmpty
        warning.isHidden = text.isEmpty
    }
}

// MARK: - Running it

extension AppModel {
    /// Writes the movie off the main thread, reporting to `movieExportStatus`.
    func exportMovie(timeline: ShowTimeline, songs: [MovieSong], to url: URL,
                     settings: MovieExportSettings, showAspect: CGFloat,
                     showName: String, lib: Library) {
        let status = MovieExportStatus(showName: showName)
        movieExportStatus = status
        let cancelled = status.cancelled

        // Every file the export can need, resolved here on the main actor.
        // The library is SQLite-backed and belongs to this thread, so the
        // writing thread gets plain URLs rather than a reference to it.
        let urls: [Int64: URL] = itemsByID.reduce(into: [:]) { $0[$1.key] = lib.url(for: $1.value) }

        Task.detached(priority: .userInitiated) {
            let media = MovieMedia { urls[$0.id] }
            do {
                let result = try MovieExport.write(
                    timeline: timeline, songs: songs, to: url, settings: settings,
                    showAspect: showAspect,
                    overlaySource: { media.image(for: $0) },
                    progress: { fraction in
                        Task { @MainActor in
                            guard self.movieExportStatus?.finished == false else { return }
                            self.movieExportStatus?.fraction = fraction
                        }
                    },
                    isCancelled: { cancelled.isSet },
                    source: { media.image(for: $0) })

                let held = media.videoSlidesHeld.count
                let summary = Self.movieSummary(result, videoSlidesHeld: held)
                let file = result.url
                await MainActor.run {
                    self.movieExportStatus?.finished = true
                    self.movieExportStatus?.fraction = 1
                    self.movieExportStatus?.file = file
                    self.movieExportStatus?.summary = summary
                }
            } catch MovieExportError.cancelled {
                await MainActor.run { self.movieExportStatus = nil }
            } catch {
                await MainActor.run {
                    self.movieExportStatus = nil
                    exportAlert("“\(showName)” wasn't exported.", "\(error).")
                }
            }
        }
    }

    nonisolated static func movieSummary(_ r: MovieExportResult, videoSlidesHeld: Int) -> String {
        let mins = Int(r.duration) / 60, secs = Int(r.duration) % 60
        var text = "Exported “\(r.url.deletingPathExtension().lastPathComponent)” — "
        text += mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        text += ", \(Int(r.size.width))×\(Int(r.size.height)) at \(r.frameRate) fps"
        text += r.hasSound ? ", with sound" : ", silent"
        // Only videos that wouldn't open are held now (E5), so this is a
        // fault worth naming rather than the normal state of things.
        if videoSlidesHeld > 0 {
            text += " · \(videoSlidesHeld) video slide\(videoSlidesHeld == 1 ? "" : "s") "
                  + "couldn't be read, and held a frame"
        }
        return text
    }
}

/// Progress while a movie is written, then a summary that stays until
/// dismissed — the shape `ExportBanner` uses for Export Show….
struct MovieExportBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.movieExportStatus {
            HStack(spacing: 12) {
                if s.finished {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(s.summary)
                    if let file = s.file {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    }
                    Button("Done") { model.movieExportStatus = nil }
                } else {
                    ProgressView(value: s.fraction)
                        .frame(width: 160)
                    Text("Exporting “\(s.showName)”: \(Int(s.fraction * 100))%")
                        .monospacedDigit()
                    Button("Cancel") { s.cancelled.isSet = true }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.bottom, 14)
        }
    }
}
