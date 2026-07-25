import CoreGraphics
import Foundation
import Testing
@testable import MiControlApp

@Suite("Remote buttons")
struct RemoteButtonsTests {
    @Test func parsesRC003ReportOneUsages() {
        let data = Data([0xF1, 0x00, 0x80, 0x00, 0x00, 0x00])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: data) == Set([UInt16(0xF1), UInt16(0x80)]))
    }

    @Test func acceptsFirmwareReportWithIncludedID() {
        let data = Data([0x01, 0x35, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: data) == Set([UInt16(0x35)]))
    }

    @Test func rejectsOtherReportsAndMalformedPayloads() {
        #expect(RemoteHIDReportParser.usages(reportID: 2, data: Data([0, 0])) == nil)
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data()) == nil)
        #expect(RemoteHIDReportParser.usages(reportID: 1, data: Data([1])) == nil)
    }

    @Test func everyKnownUsageHasDefaultBinding() {
        for button in Set(RemoteButton.usageMap.values) {
            #expect(AppSettings.defaultBindings[button] != nil, Comment(rawValue: button.rawValue))
        }
    }

    @Test func usesVerifiedRC003UsageTable() {
        #expect(RemoteButton.usageMap == [
            0x28: .ok,
            0x35: .tv,
            0x4A: .home,
            0x4F: .right,
            0x50: .left,
            0x51: .down,
            0x52: .up,
            0x65: .menu,
            0x66: .power,
            0x80: .volumeUp,
            0x81: .volumeDown,
            0xF1: .back,
        ])
    }

    @Test func HIDPermissionGateFailsClosed() {
        #expect(!HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: false,
            accessibilityGranted: true
        ))
        #expect(!HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: false
        ))
        #expect(HIDPermissionGate.canMonitor(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        ))
    }

    @Test func HIDPermissionRequestsAreSequentialAndOptIn() {
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: false,
            inputMonitoringGranted: false,
            accessibilityGranted: false
        ) == .none)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: false,
            accessibilityGranted: false
        ) == .inputMonitoring)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: false
        ) == .accessibility)
        #expect(HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        ) == .none)
    }

    @Test func macroShortcutRoundTrips() throws {
        let action = ButtonAction.macro([
            MacroStep(keyCode: 8, modifiers: CGEventFlags.maskCommand.rawValue),
            MacroStep(keyCode: 9, modifiers: CGEventFlags.maskCommand.rawValue),
        ])
        let data = try JSONEncoder().encode(["home": action])
        let decoded = try JSONDecoder().decode([String: ButtonAction].self, from: data)
        #expect(decoded["home"] == action)
        #expect(action.displayName.contains("→"))
        #expect(action.isMacro)
    }

    @Test func openAppShortcutRoundTrips() throws {
        let action = ButtonAction.openApp(bundleID: "com.apple.Safari")
        let data = try JSONEncoder().encode(["tv": action])
        let decoded = try JSONDecoder().decode([String: ButtonAction].self, from: data)
        #expect(decoded["tv"] == action)
        #expect(action.isOpenApp)
        #expect(action.suppressesKeyRepeat)
        #expect(action.displayName.hasPrefix("打开 "))
    }

    @Test func codexShortcutRoundTrips() throws {
        let action = ButtonAction.codex(.submit)
        let data = try JSONEncoder().encode(["ok": action])
        let decoded = try JSONDecoder().decode([String: ButtonAction].self, from: data)
        #expect(decoded["ok"] == action)
        #expect(action.isCodexAction)
        #expect(action.suppressesKeyRepeat)
        #expect(action.displayName == "Codex 提交")
    }

    @Test func customShortcutRoundTrips() throws {
        let action = ButtonAction.custom(
            keyCode: 35,
            modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
        )
        let data = try JSONEncoder().encode(["tv": action])
        let decoded = try JSONDecoder().decode([String: ButtonAction].self, from: data)
        #expect(decoded["tv"] == action)
        #expect(action.displayName == "⇧⌘P")
    }

    @Test func legacyPresetStringsStillDecode() throws {
        let data = Data(#""escape""#.utf8)
        let decoded = try JSONDecoder().decode(ButtonAction.self, from: data)
        #expect(decoded == .escape)
    }

    @Test func savedBindingsMergeWithDefaults() throws {
        let suiteName = "MiControlAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let saved = try JSONEncoder().encode([RemoteButton.back.rawValue: ButtonAction.disabled])
        defaults.set(saved, forKey: "buttonBindings")
        let settings = AppSettings(defaults: defaults)

        #expect(settings.action(for: .back) == .disabled)
        #expect(settings.action(for: .up) == .arrowUp)
    }

    @Test func speechDestinationDefaultsToFrontmostAndAcceptsCodexDraft() throws {
        let suiteName = "MiControlAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettings(defaults: defaults).speechDestination == .frontmost)

        defaults.set("codexDraft", forKey: "speechDestination")
        #expect(AppSettings(defaults: defaults).speechDestination == .codexDraft)
    }

    @Test func migratesLegacyExclusiveToggleToCustomMappingToggle() throws {
        let suiteName = "MiControlAppTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "exclusiveHID")
        let settings = AppSettings(defaults: defaults)

        #expect(settings.customMappingEnabled)
    }

    @Test func nativeEventDescriptorsCoverPotentialDuplicateEvents() {
        #expect(RemoteButton.up.nativeEvent == .keyboard(keyCode: 126))
        #expect(RemoteButton.ok.nativeEvent == .keyboard(keyCode: 36))
        #expect(RemoteButton.volumeUp.nativeEvent == .systemKey(type: 0))
        #expect(RemoteButton.back.nativeEvent == nil)
    }
}
