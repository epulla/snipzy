import Foundation
import Testing
@testable import Snipzy

@MainActor @Suite
struct CaptureHistoryTests {
    private func setup() throws -> (CaptureHistory, URL, UserDefaults, String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "SnipzyHistory-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (CaptureHistory(directory: directory, defaults: defaults), directory, defaults, suite)
    }

    @Test func addListsNewestFirst() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try #require(history.add(Data([1]), date: old))
        let second = try #require(history.add(Data([2]), date: old.addingTimeInterval(1)))
        #expect(history.entries().map(\.id) == [second, first])
    }

    @Test func addPrunesOldestBeyondLimit() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        history.setLimit(2)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try #require(history.add(Data([1]), date: date))
        _ = history.add(Data([2]), date: date.addingTimeInterval(1))
        _ = history.add(Data([3]), date: date.addingTimeInterval(2))
        #expect(!history.entries().contains { $0.id == old })
        #expect(history.entries().count == 2)
    }

    @Test func replaceKeepsPositionAndDate() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = try #require(history.add(Data([1]), date: date))
        let before = try #require(history.entries().first)
        history.replace(id: id, with: Data([9]))
        #expect(try Data(contentsOf: before.url) == Data([9]))
        #expect(history.entries().first == before)
    }

    @Test func setLimitPersistsAndShrinks() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in 0..<3 { _ = history.add(Data([UInt8(offset)]), date: date.addingTimeInterval(Double(offset))) }
        history.setLimit(1)
        #expect(history.limit == 1)
        #expect(defaults.integer(forKey: CaptureHistory.limitKey) == 1)
        #expect(history.entries().count == 1)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).count == 1)
    }

    @Test func removeDeletesOnlyThatEntry() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let keep = try #require(history.add(Data([1]), date: date))
        let gone = try #require(history.add(Data([2]), date: date.addingTimeInterval(1)))
        let url = try #require(history.entries().first { $0.id == gone }).url

        history.remove(id: gone)

        #expect(history.entries().map(\.id) == [keep])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

        @Test func clearEmptiesDirectory() throws {
        let (history, directory, defaults, suite) = try setup()
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        _ = history.add(Data([1]))
        history.clear()
        #expect(history.entries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
