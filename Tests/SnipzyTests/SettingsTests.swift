import AppKit
import Testing
@testable import Snipzy

@MainActor @Suite
struct SettingsTests {
    @Test
    func autoCopyIsOffByDefaultAndCheckboxPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "SnipzySettingsTests"))
        defaults.removePersistentDomain(forName: "SnipzySettingsTests")
        defer { defaults.removePersistentDomain(forName: "SnipzySettingsTests") }
        let settings = SettingsWindowController(defaults: defaults)
        #expect(settings.autoCopyCheckbox.state == .off)

        settings.autoCopyCheckbox.performClick(nil)

        #expect(defaults.bool(forKey: SettingsWindowController.autoCopyKey))
        #expect(SettingsWindowController(defaults: defaults).autoCopyCheckbox.state == .on)
    }
}
