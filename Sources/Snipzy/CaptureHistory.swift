import Foundation

struct HistoryEntry: Equatable {
    let id: String
    let url: URL
    let date: Date
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
            return id
        } catch { return nil }
    }

    func replace(id: String, with png: Data) {
        let url = directory.appendingPathComponent("\(id).png")
        guard entries().contains(where: { $0.id == id }) else { return }
        try? png.write(to: url, options: .atomic)
    }

    func clear() {
        for entry in entries() { try? FileManager.default.removeItem(at: entry.url) }
    }

    func setLimit(_ n: Int) {
        defaults.set(min(max(n, Self.limitRange.lowerBound), Self.limitRange.upperBound), forKey: Self.limitKey)
        prune()
    }

    private func prune() {
        for entry in entries().dropFirst(limit) { try? FileManager.default.removeItem(at: entry.url) }
    }
}
