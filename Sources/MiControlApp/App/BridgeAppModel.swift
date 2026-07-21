import AppKit
import Combine
import Foundation

final class BridgeAppModel: ObservableObject, XiaomiBluetoothBridgeDelegate {
    let settings = AppSettings()

    @Published private(set) var connectionStatus = "正在初始化蓝牙"
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var hidStatus = "按键映射未启用"
    @Published private(set) var isStreaming = false
    @Published private(set) var voiceShortcutStatus = "正在准备语音输入"
    @Published private(set) var speechStatus = "系统听写待命"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var liveTranscript = ""

    private let speechTranscriber = DirectSpeechTranscriber()
    private let voiceFunctionMapper = RemoteVoiceFunctionMapper()
    private let speechOverlay = SpeechOverlayController.shared
    private var overlayLevelEMA = 0.0
    private lazy var bluetoothBridge = XiaomiBluetoothBridge(settings: settings, delegate: self)
    private lazy var hidMonitor: HIDRemoteMonitor = {
        let monitor = HIDRemoteMonitor(settings: settings)
        monitor.onStatus = { [weak self] value in
            self?.hidStatus = value
        }
        return monitor
    }()
    private var started = false
    private var terminationObserver: NSObjectProtocol?
    private var speechSessionActive = false
    private var permissionRetryTimer: Timer?
    private var lastHIDRetryAt = Date.distantPast
    private var didPresentPermissionAlert = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        AppLogger.shared.write("APP START version=\(version)")
        speechTranscriber.onPartial = { [weak self] text in
            guard let self else { return }
            self.lastTranscript = text
            self.liveTranscript = text
            self.speechStatus = "识别中：\(text.prefix(36))"
            self.speechOverlay.update(transcript: text, audioLevel: self.overlayLevelEMA)
        }
        speechTranscriber.onFinal = { [weak self] text in
            self?.lastTranscript = text
        }
        speechTranscriber.onStatus = { [weak self] status in
            self?.speechStatus = status
        }

        _ = KeyboardInjector.requestAccessibilityAccess()
        _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        DirectSpeechTranscriber.requestAuthorization { [weak self] granted in
            guard let self else { return }
            if granted {
                if !self.speechStatus.hasPrefix("识别中"),
                   !self.speechStatus.hasPrefix("系统听写中"),
                   !self.speechStatus.hasPrefix("已粘贴")
                {
                    self.speechStatus = "系统听写待命（语音识别已授权）"
                }
            } else {
                self.speechStatus = "请在系统设置勾选「语音识别」"
            }
        }

        applyHIDSettings()
        clearLegacyVoiceFnMapping()
        refreshSpeechPermissionStatus()
        updateVoiceModeStatus()
        startPermissionRetryLoop()
        bluetoothBridge.start()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        DispatchQueue.main.async { [weak self] in
            self?.presentPermissionAlertIfNeeded()
        }
    }

    func stop() {
        guard started else { return }
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        bluetoothBridge.stop()
        hidMonitor.stop()
        if speechSessionActive {
            speechTranscriber.stop { _ in }
            speechSessionActive = false
        }
        speechOverlay.hide(after: 0)
        voiceFunctionMapper.restore()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        started = false
        AppLogger.shared.write("APP STOP")
    }

    private func startPermissionRetryLoop() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.started else { return }

            let inputOK = HIDRemoteMonitor.isInputMonitoringGranted
            let axOK = KeyboardInjector.isAccessibilityTrusted
            let tapOK = self.hidMonitor.isEventTapRunning
            let managerOK = self.hidMonitor.isManagerOpen
            let seizeOK = self.hidMonitor.hasSeizedDevice
            let micBlocked = tapOK || seizeOK
            let fullyReady = inputOK && axOK && micBlocked && (managerOK || tapOK)

            if fullyReady {
                if !self.speechStatus.hasPrefix("识别中"),
                   !self.speechStatus.hasPrefix("系统听写中"),
                   !self.speechStatus.hasPrefix("已粘贴"),
                   !self.speechStatus.hasPrefix("已复制")
                {
                    self.speechStatus = "权限已就绪：系统听写可用"
                }
                AppLogger.shared.write(
                    "HID READY input=\(inputOK) ax=\(axOK) tap=\(tapOK) seize=\(seizeOK)"
                )
                self.permissionRetryTimer?.invalidate()
                self.permissionRetryTimer = nil
                return
            }

            if (inputOK || axOK), (!tapOK || !managerOK) {
                let now = Date()
                if now.timeIntervalSince(self.lastHIDRetryAt) >= 2.5 {
                    self.lastHIDRetryAt = now
                    AppLogger.shared.write(
                        "HID RETRY input=\(inputOK) ax=\(axOK) tap=\(tapOK) manager=\(managerOK)"
                    )
                    self.applyHIDSettings()
                }
            }

            if !self.speechStatus.hasPrefix("识别中"),
               !self.speechStatus.hasPrefix("系统听写中")
            {
                self.speechStatus =
                    "请授权：辅助功能=\(axOK ? "✓" : "×") 输入监控=\(inputOK ? "✓" : "×")"
            }
        }
    }

    private func presentPermissionAlertIfNeeded() {
        let inputOK = HIDRemoteMonitor.isInputMonitoringGranted
        let axOK = KeyboardInjector.isAccessibilityTrusted
        guard !(inputOK && axOK) else { return }
        guard !didPresentPermissionAlert else { return }
        didPresentPermissionAlert = true

        requestAccessibilityPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.requestInputMonitoringPermission()
        }

        let alert = NSAlert()
        alert.messageText = "还缺系统权限（与「语音识别」不是同一项）"
        alert.informativeText = """
        当前：辅助功能 \(axOK ? "已开" : "未开")，输入监控 \(inputOK ? "已开" : "未开")。

        请勾选 /Applications 里的「MiControlApp」。
        · 辅助功能：拦截麦克风键 + 自动粘贴
        · 输入监控：独占遥控器 HID
        · 语音识别：另算一项，在「隐私 → 语音识别」

        已打开系统设置。用「＋」添加应用后勾选即可。
        """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func reconnect() {
        bluetoothBridge.reconnectNow()
    }

    func applyHIDSettings() {
        requestNextHIDPermissionIfNeeded()
        hidMonitor.start()
        hidMonitor.applyVoiceMicPolicy()
        hidStatus = hidMonitor.status
    }

    private func updateVoiceModeStatus() {
        voiceShortcutStatus = "系统听写：先点 Cursor Agent 输入框，再按住麦克风"
        if speechStatus.hasPrefix("识别中") || speechStatus.hasPrefix("系统听写中") {
            return
        }
        switch DirectSpeechTranscriber.authorizationStatus {
        case .authorized:
            speechStatus = "系统听写待命（已拦截遥控器 F5）"
        case .denied, .restricted:
            speechStatus = "语音识别被拒绝：系统设置 → 隐私 → 语音识别"
        case .notDetermined:
            speechStatus = "首次使用将请求语音识别权限"
        @unknown default:
            speechStatus = "语音识别状态未知"
        }
    }

    private func requestNextHIDPermissionIfNeeded() {
        // 听写始终需要权限；映射仅决定是否额外注入按键
        if !HIDRemoteMonitor.isInputMonitoringGranted {
            _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        }
        if !KeyboardInjector.isAccessibilityTrusted {
            _ = KeyboardInjector.requestAccessibilityAccess()
        }
    }

    func requestInputMonitoringPermission() {
        _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    func requestAccessibilityPermission() {
        _ = KeyboardInjector.requestAccessibilityAccess()
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestSpeechRecognitionPermission() {
        _ = DirectSpeechTranscriber.requestAuthorization()
        openPrivacyPane("Privacy_SpeechRecognition")
        refreshSpeechPermissionStatus()
    }

    func refreshSpeechPermissionStatus() {
        if speechStatus.hasPrefix("识别中") || speechStatus.hasPrefix("系统听写中") {
            return
        }
        switch DirectSpeechTranscriber.authorizationStatus {
        case .authorized:
            speechStatus = "系统听写待命"
        case .denied, .restricted:
            speechStatus = "语音识别被拒绝：系统设置 → 隐私 → 语音识别"
        case .notDetermined:
            speechStatus = "首次使用将请求语音识别权限"
        @unknown default:
            speechStatus = "语音识别状态未知"
        }
    }

    func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.shared.logURL])
    }

    func openProjectFolder() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        var candidate = executable.deletingLastPathComponent()
        if candidate.path.contains(".app/Contents/MacOS") {
            candidate.deleteLastPathComponent()
            candidate.deleteLastPathComponent()
            candidate.deleteLastPathComponent()
        }
        NSWorkspace.shared.open(candidate)
    }

    private func openPrivacyPane(_ pane: String) {
        let modern: [String: String] = [
            "Privacy_Accessibility":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "Privacy_ListenEvent":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "Privacy_SpeechRecognition":
                "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
        ]
        if let value = modern[pane], let url = URL(string: value) {
            NSWorkspace.shared.open(url)
            return
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didChange state: BluetoothBridgeState
    ) {
        connectionStatus = state.displayText
        if case .ready = state {
            clearLegacyVoiceFnMapping()
        } else {
            batteryPercent = nil
        }
    }

    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didUpdateBatteryLevel percent: Int?
    ) {
        batteryPercent = percent
    }

    func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge) {
        isStreaming = true
        liveTranscript = ""
        overlayLevelEMA = 0
        speechOverlay.show()
        beginSystemSpeechSession()
    }

    func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge) {
        isStreaming = false
        endSystemSpeechSession()
    }

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDecode samples: [Int16]) {
        speechTranscriber.append(samples: samples)
        guard isStreaming else { return }
        let level = Self.normalizedLevel(samples: samples)
        overlayLevelEMA = overlayLevelEMA * 0.65 + level * 0.35
        speechOverlay.update(transcript: liveTranscript, audioLevel: overlayLevelEMA)
    }

    private func beginSystemSpeechSession() {
        if !DirectSpeechTranscriber.isAuthorized {
            _ = DirectSpeechTranscriber.requestAuthorization()
        }
        speechSessionActive = true
        lastTranscript = ""
        speechTranscriber.start(localeIdentifier: settings.speechLocale)
        voiceShortcutStatus = "系统听写中：松开麦克风键后粘贴文字"
        AppLogger.shared.write("SPEECH session_begin")
    }

    private func endSystemSpeechSession() {
        guard speechSessionActive else { return }
        speechSessionActive = false
        speechTranscriber.stop { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastTranscript = trimmed
            self.liveTranscript = trimmed
            if !trimmed.isEmpty {
                self.speechOverlay.update(transcript: trimmed, audioLevel: 0.15)
            }

            guard !trimmed.isEmpty else {
                self.speechStatus = "未识别到有效语音"
                self.voiceShortcutStatus = "系统听写：按住麦克风 → 转写并粘贴到输入框"
                self.speechOverlay.hide(after: 0.35)
                return
            }
            let pasted = KeyboardInjector.pasteText(trimmed)
            if pasted {
                self.speechStatus = "已粘贴：\(trimmed.prefix(40))"
                self.voiceShortcutStatus = "已粘贴识别文字"
                AppLogger.shared.write("SPEECH pasted chars=\(trimmed.count)")
            } else {
                self.speechStatus = "已复制，请点 Agent 输入框后按 ⌘V：\(trimmed.prefix(28))"
                self.voiceShortcutStatus = "粘贴失败：请开启辅助功能后重试"
                self.requestAccessibilityPermission()
                AppLogger.shared.write("SPEECH paste_failed clipboard_chars=\(trimmed.count)")
            }
            self.speechOverlay.hide(after: 0.55)
        }
    }

    /// 粗略 RMS → 0…1，供声波动画使用。
    private static func normalizedLevel(samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            let v = Double(sample) / Double(Int16.max)
            sum += v * v
        }
        let rms = sqrt(sum / Double(samples.count))
        // 遥控器近讲通常电平偏低，略放大后再压到 0…1
        return min(1, rms * 4.5)
    }

    /// 清除可能残留的 F5→Fn 硬件映射（旧虚拟麦克风路径），避免 Globe/顶部搜索。
    private func clearLegacyVoiceFnMapping() {
        _ = voiceFunctionMapper.forceRemoveVoiceKeyMapping()
        if !isStreaming {
            voiceShortcutStatus = "系统听写：先点 Agent 输入框，再按住麦克风"
        }
    }
}
