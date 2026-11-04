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
        let settings = SettingsWindowController(defaults: defaults, history: history(defaults))
        #expect(settings.autoCopyCheckbox.state == .off)
        #expect(settings.loginCheckbox.state == .off)

        settings.autoCopyCheckbox.performClick(nil)

        #expect(defaults.bool(forKey: SettingsWindowController.autoCopyKey))
        #expect(SettingsWindowController(defaults: defaults, history: history(defaults)).autoCopyCheckbox.state == .on)
    }

    @Test
    func launchAtLoginRegistersOnlyOnFirstRun() throws {
        let defaults = try #require(UserDefaults(suiteName: "SnipzySettingsTests"))
        defaults.removePersistentDomain(forName: "SnipzySettingsTests")
        defer { defaults.removePersistentDomain(forName: "SnipzySettingsTests") }
        var registrations = 0

        SettingsWindowController.applyLaunchAtLoginDefault(defaults: defaults) { registrations += 1 }
        SettingsWindowController.applyLaunchAtLoginDefault(defaults: defaults) { registrations += 1 }

        #expect(registrations == 1)
    }

    @Test
    func historyLimitDefaultsToTenAndStepperPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: "SnipzySettingsTests"))
        defaults.removePersistentDomain(forName: "SnipzySettingsTests")
        defer { defaults.removePersistentDomain(forName: "SnipzySettingsTests") }
        let settings = SettingsWindowController(defaults: defaults, history: history(defaults))
        #expect(settings.historyLimitField.integerValue == 10)

        settings.historyLimitStepper.integerValue = 25
        settings.historyLimitStepper.sendAction(settings.historyLimitStepper.action, to: settings.historyLimitStepper.target)

        #expect(defaults.integer(forKey: CaptureHistory.limitKey) == 25)
        #expect(SettingsWindowController(defaults: defaults, history: history(defaults)).historyLimitField.integerValue == 25)
    }

    private func history(_ defaults: UserDefaults) -> CaptureHistory {
        CaptureHistory(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: defaults)
    }
}
