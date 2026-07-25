import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum KeyboardInjector {
    static let syntheticEventMarker: Int64 = 0x5849_414F
    static let codexBundleID = "com.openai.codex"
    private static let macroStepInterval: TimeInterval = 0.05
    private static var macroPlaybackGeneration = 0

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func send(_ action: ButtonAction) -> Bool {
        guard !action.isDisabled else { return true }

        // 打开 App 不依赖辅助功能注入。
        if case let .openApp(bundleID) = action {
            return openApplication(bundleID: bundleID)
        }
        if case let .codex(codexAction) = action {
            sendCodexAction(codexAction)
            return true
        }

        guard isAccessibilityTrusted else { return false }

        switch action {
        case .disabled, .openApp, .codex:
            return true
        case .escape:
            postKey(code: 53)
        case .returnKey:
            postKey(code: 36)
        case .arrowUp:
            postKey(code: 126)
        case .arrowDown:
            postKey(code: 125)
        case .arrowLeft:
            postKey(code: 123)
        case .arrowRight:
            postKey(code: 124)
        case .deleteBackward:
            postKey(code: 51)
        case .showDesktop:
            postKey(code: 103, flags: .maskSecondaryFn)
        case .contextMenu:
            postKey(code: 109, flags: .maskShift)
        case .appSwitcher:
            postKey(code: 48, flags: .maskCommand)
        case .volumeUp:
            postSystemKey(type: 0)
        case .volumeDown:
            postSystemKey(type: 1)
        case .volumeMute:
            postSystemKey(type: 7)
        case .playPause:
            postSystemKey(type: 16)
        case let .custom(keyCode, modifiers):
            postKey(code: CGKeyCode(keyCode), flags: CGEventFlags(rawValue: modifiers))
        case let .macro(steps):
            playMacro(steps)
        }
        return true
    }

    @discardableResult
    static func sendCodexPrompt(_ text: String, submit: Bool) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        guard openApplication(bundleID: codexBundleID) else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            _ = pasteText(value)
            if submit {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    postKey(code: 36)
                }
            }
        }
        AppLogger.shared.write("CODEX prompt chars=\(value.count) submit=\(submit)")
        return true
    }

    @discardableResult
    static func openApplication(bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            AppLogger.shared.write("OPEN APP missing_bundle_id")
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            AppLogger.shared.write("OPEN APP not_found bundle=\(id)")
            return true
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                AppLogger.shared.write("OPEN APP failed bundle=\(id) error=\(error.localizedDescription)")
            } else {
                AppLogger.shared.write("OPEN APP opened bundle=\(id)")
            }
        }
        return true
    }

    private static func sendCodexAction(_ action: CodexRemoteAction) {
        _ = openApplication(bundleID: codexBundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch action {
            case .activate:
                break
            case .submit:
                postKey(code: 36)
            case .stop:
                postKey(code: 53)
            case .commandPalette:
                postKey(code: 40, flags: .maskCommand)
            case .newTask:
                postKey(code: 45, flags: .maskCommand)
            }
            AppLogger.shared.write("CODEX action=\(action.rawValue)")
        }
    }

    private static func playMacro(_ steps: [MacroStep]) {
        let limited = Array(steps.prefix(ButtonAction.macroStepLimit))
        guard !limited.isEmpty else { return }
        macroPlaybackGeneration &+= 1
        let generation = macroPlaybackGeneration
        for (index, step) in limited.enumerated() {
            let delay = Self.macroStepInterval * Double(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard generation == macroPlaybackGeneration else { return }
                postKey(
                    code: CGKeyCode(step.keyCode),
                    flags: CGEventFlags(rawValue: step.modifiers)
                )
            }
        }
        AppLogger.shared.write("MACRO play steps=\(limited.count)")
    }

    /// 把识别结果写入当前前台输入框。
    /// 优先 AX 选区插入，其次 Cmd+V；无辅助功能时保留剪贴板内容供手动粘贴。
    @discardableResult
    static func pasteText(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)

        guard isAccessibilityTrusted else {
            requestAccessibilityAccess()
            AppLogger.shared.write("PASTE blocked_no_accessibility clipboard_ready=1")
            return false
        }

        if insertSelectedText(value) {
            AppLogger.shared.write("PASTE via_ax_selected_text chars=\(value.count)")
            scheduleClipboardRestore(previous: previous, delay: 1.2)
            return true
        }

        postKey(code: 9, flags: .maskCommand) // V
        AppLogger.shared.write("PASTE via_cmd_v chars=\(value.count)")
        scheduleClipboardRestore(previous: previous, delay: 0.6)
        return true
    }

    private static func scheduleClipboardRestore(previous: String?, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pasteboardRestoreIfUnchanged(previous: previous)
        }
    }

    private static func pasteboardRestoreIfUnchanged(previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }

    /// 往当前焦点控件的选区写入文字（比 Cmd+V 少一次按键合成，Cursor 输入框更稳）。
    private static func insertSelectedText(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard copyStatus == .success, let focusedRef else {
            AppLogger.shared.write("PASTE ax_focus_missing status=\(copyStatus.rawValue)")
            return false
        }
        let focused = focusedRef as! AXUIElement

        let selectedStatus = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedStatus == .success {
            return true
        }

        var supportsValue: DarwinBoolean = false
        AXUIElementIsAttributeSettable(
            focused,
            kAXValueAttribute as CFString,
            &supportsValue
        )
        guard supportsValue.boolValue else {
            AppLogger.shared.write(
                "PASTE ax_insert_unsupported selected=\(selectedStatus.rawValue)"
            )
            return false
        }

        var currentRef: CFTypeRef?
        let currentStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &currentRef
        )
        let current = (currentStatus == .success ? currentRef as? String : nil) ?? ""
        let combined = current + text
        let setStatus = AXUIElementSetAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            combined as CFTypeRef
        )
        if setStatus == .success {
            return true
        }
        AppLogger.shared.write(
            "PASTE ax_value_failed selected=\(selectedStatus.rawValue) value=\(setStatus.rawValue)"
        )
        return false
    }

    private static func postKey(code: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postSystemKey(type: Int32) {
        postSystemKey(type: type, isDown: true)
        postSystemKey(type: type, isDown: false)
    }

    private static func postSystemKey(type: Int32, isDown: Bool) {
        let keyState = isDown ? 0xA : 0xB
        let data1 = Int((type << 16) | Int32(keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        guard let cgEvent = event.cgEvent else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
