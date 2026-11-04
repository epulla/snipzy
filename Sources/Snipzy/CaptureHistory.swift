import AppKit
import ImageIO

extension Notification.Name {
    /// Posted by `CaptureHistory`; `userInfo["id"]` is set when only that entry's image changed.
    static let captureHistoryDidChange = Notification.Name("SnipzyCaptureHistoryDidChange")
}

struct HistoryEntry: Equatable {
    let id: String
    let url: URL
    let date: Date

    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// Downsampled with ImageIO so lists never hold full-size captures.
    func thumbnail(fitting size: NSSize) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              image.width > 0, image.height > 0 else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(size.width / width, size.height / height, 1)
        return NSImage(cgImage: image, size: NSSize(width: width * scale, height: height * scale))
    }
}

@MainActor
final class CaptureHistory {
    static let limitKey = "historyLimit"
    static let defaultLimit = 10
    static let limitRange = 1...100
    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Snipzy/History")

    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL = CaptureHistory.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
    }

    var limit: Int {
        defaults.object(forKey: Self.limitKey) == nil
            ? Self.defaultLimit
            : min(max(defaults.integer(forKey: Self.limitKey), Self.limitRange.lowerBound), Self.limitRange.upperBound)
    }

    func entries() -> [HistoryEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "png",
                  let stamp = Int64(url.deletingPathExtension().lastPathComponent.split(separator: "-").first ?? "")
            else { return nil }
            return HistoryEntry(id: url.deletingPathExtension().lastPathComponent, url: url,
                                date: Date(timeIntervalSince1970: Double(stamp) / 1000))
        }.sorted { $0.date > $1.date }
    }

    @discardableResult
    func add(_ png: Data, date: Date = Date()) -> String? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = "\(Int64(date.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
            try png.write(to: directory.appendingPathComponent("\(id).png"), options: .atomic)
            prune()
            notify()
            return id
        } catch { return nil }
    }

    func replace(id: String, with png: Data) {
        let url = directory.appendingPathComponent("\(id).png")
        guard entries().contains(where: { $0.id == id }) else { return }
        try? png.write(to: url, options: .atomic)
        notify(id: id)
    }

    func remove(id: String) throws {
        guard let entry = entries().first(where: { $0.id == id }) else { return }
        try FileManager.default.removeItem(at: entry.url)
        notify()
    }

    func clear() {
        for entry in entries() { try? FileManager.default.removeItem(at: entry.url) }
        notify()
    }

    func setLimit(_ n: Int) {
        defaults.set(min(max(n, Self.limitRange.lowerBound), Self.limitRange.upperBound), forKey: Self.limitKey)
        prune()
        notify()
    }

    private func notify(id: String? = nil) {
        NotificationCenter.default.post(name: .captureHistoryDidChange, object: self, userInfo: id.map { ["id": $0] })
    }

    private func prune() {
        for entry in entries().dropFirst(limit) { try? FileManager.default.removeItem(at: entry.url) }
    }
}

/// Keeps each annotated entry's original image and annotations while the app runs, so drawings stay editable when switching back.
@MainActor
final class HistorySession {
    let history: CaptureHistory
    private var states: [String: (image: NSImage, annotations: [Annotation])] = [:]

    init(history: CaptureHistory) {
        self.history = history
    }

    func store(_ id: String, image: NSImage, annotations: [Annotation]) {
        let ids = Set(history.entries().map(\.id))
        states = states.filter { ids.contains($0.key) }
        states[id] = annotations.isEmpty ? nil : (image, annotations)
    }

    /// Keeps the editable state if the file could not be deleted.
    func remove(_ id: String) throws {
        try history.remove(id: id)
        states[id] = nil
    }

    /// Session state if the entry was annotated this run, else the history PNG with no annotations.
    func state(for id: String) -> (image: NSImage, annotations: [Annotation])? {
        guard let entry = history.entries().first(where: { $0.id == id }) else { return nil }
        return states[id] ?? NSImage(contentsOf: entry.url).map { ($0, []) }
    }
}
