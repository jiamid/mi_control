import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject var settings: AppSettings
    @StateObject private var recorder = KeyRecordingController()
    @State private var selectedRemoteButton: RemoteButton = .ok
    @State private var showMappingPopover = false
    @State private var permissionPulse = 0

    init(model: BridgeAppModel) {
        self.model = model
        settings = model.settings
        _recorder = StateObject(wrappedValue: KeyRecordingController())
    }

    var body: some View {
        TabView {
            mappingTab
                .tabItem { Label("按键", systemImage: "keyboard") }
            connectionTab
                .tabItem { Label("连接与权限", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 900, height: 640)
        .padding(14)
        .onDisappear { recorder.cancel() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            permissionPulse &+= 1
        }
    }

    // MARK: - 连接与权限

    private var connectionTab: some View {
        let _ = permissionPulse
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard(title: "遥控器", subtitle: "蓝牙连接与语音触发状态") {
                    statusLine("蓝牙", model.connectionStatus)
                    statusLine("语音", model.isStreaming ? "进行中" : "待机")
                    statusLine("触发", model.voiceShortcutStatus)
                    Divider().opacity(0.35)
                    Button("立即重新连接") { model.reconnect() }
                        .controlSize(.regular)
                }

                settingsCard(
                    title: "系统权限",
                    subtitle: "听写、拦截麦克风键、粘贴都依赖这些开关"
                ) {
                    permissionStatusRow(
                        title: "辅助功能",
                        detail: "拦截 F5 + 自动粘贴到输入框",
                        granted: KeyboardInjector.isAccessibilityTrusted
                    ) { model.requestAccessibilityPermission() }

                    permissionStatusRow(
                        title: "输入监控",
                        detail: "读取 / 独占 RC003 HID",
                        granted: HIDRemoteMonitor.isInputMonitoringGranted
                    ) { model.requestInputMonitoringPermission() }

                    permissionStatusRow(
                        title: "语音识别",
                        detail: "系统听写转文字",
                        granted: DirectSpeechTranscriber.isAuthorized
                    ) { model.requestSpeechRecognitionPermission() }

                    permissionStatusRow(
                        title: "蓝牙",
                        detail: "连接遥控器并接收 ATVV 语音",
                        granted: nil
                    ) {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.BluetoothSettings"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                settingsCard(title: "诊断", subtitle: nil) {
                    Button("在 Finder 中显示日志") { model.openLogFolder() }
                    Text("日志不含语音内容、蓝牙地址或外设 UUID。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 按键

    private var mappingTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            mappingHeader

            RemoteControlDiagram(
                selectedButton: $selectedRemoteButton,
                showMappingPopover: $showMappingPopover,
                voiceActive: model.isStreaming,
                actionLabel: { settings.action(for: $0).displayName },
                mappingPopover: { mappingPopover }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var mappingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(
                get: { settings.customMappingEnabled },
                set: { enabled in
                    settings.customMappingEnabled = enabled
                    model.applyHIDSettings()
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("自定义按键映射")
                        .font(.headline)
                    Text(model.hidStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .toggleStyle(.switch)

            Spacer()

            Button("恢复默认") {
                recorder.cancel()
                settings.resetBindings()
                selectedRemoteButton = .ok
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var mappingPopover: some View {
        let action = settings.action(for: selectedRemoteButton)
        let recording = recorder.isRecording(selectedRemoteButton)
        let canEdit = settings.customMappingEnabled || recording

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedRemoteButton.displayName)
                    .font(.headline)
                Text(selectedRemoteButton.shortLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
                Spacer()
                Text(String(format: "HID 0x%02X", selectedRemoteButton.hidUsage))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if !settings.customMappingEnabled && !recording {
                Text("请先打开上方「自定义按键映射」开关")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if recording {
                recordingBanner
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前动作")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(action.displayName)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canEdit {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("更改映射")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(ButtonAction.presetCases) { preset in
                            Button(preset.displayName) {
                                settings.setAction(preset, for: selectedRemoteButton)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        }
                        Divider()
                        Button("打开 App…") {
                            pickOpenApp(for: selectedRemoteButton)
                        }
                        .buttonStyle(.plain)
                        Button("录制单键快捷键…") {
                            recorder.begin(
                                for: selectedRemoteButton,
                                asMacro: false,
                                settings: settings
                            )
                        }
                        .buttonStyle(.plain)
                        Button("录制宏（多步）…") {
                            recorder.begin(
                                for: selectedRemoteButton,
                                asMacro: true,
                                settings: settings
                            )
                        }
                        .buttonStyle(.plain)
                        if action.isUserRecorded {
                            Button("重录") {
                                recorder.begin(
                                    for: selectedRemoteButton,
                                    asMacro: action.isMacro,
                                    settings: settings
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recorder.isMacro {
                Text(
                    recorder.draft.isEmpty
                        ? "宏录制中 · 0/\(ButtonAction.macroStepLimit) · 依次按下每一步"
                        : "宏 \(recorder.draft.count)/\(ButtonAction.macroStepLimit)：\(recorder.draft.map(\.displayName).joined(separator: " → "))"
                )
                .font(.callout.weight(.medium))
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("撤销") { recorder.undoLastStep() }
                        .disabled(recorder.draft.isEmpty)
                    Button("完成") { recorder.finish(settings: settings) }
                        .disabled(recorder.draft.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    Button("取消") { recorder.cancel() }
                    Spacer()
                    Text("Esc 取消")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .controlSize(.small)
            } else {
                HStack {
                    Text("等待按键… 按下 ⌘/⌥/⇧/⌃ + 任意键")
                        .font(.callout.weight(.medium))
                        .foregroundColor(.orange)
                    Spacer()
                    Button("取消") { recorder.cancel() }
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pickOpenApp(for button: RemoteButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "选择按下该键时要打开的应用"
        panel.prompt = "选择"
        panel.title = "打开 App"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleID.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无法读取该应用"
            alert.informativeText = "请选择一个普通的 .app 应用。"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        settings.setAction(.openApp(bundleID: bundleID), for: button)
        AppLogger.shared.write(
            "BINDING openApp button=\(button.rawValue) bundle=\(bundleID)"
        )
    }

    private func permissionStatusRow(
        title: String,
        detail: String,
        granted: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let granted {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(granted ? .green : .orange)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let granted {
                        Text(granted ? "已授权" : "未授权")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(granted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .foregroundColor(granted ? .green : .orange)
                            .clipShape(Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(granted == false ? "去开启" : "打开设置", action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared chrome

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}
