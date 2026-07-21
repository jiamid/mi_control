import Foundation
import IOKit.hid
import IOKit.hidsystem

private func hidDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { monitor.deviceDidMatch(result: result, device: device) }
}

private func hidDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { monitor.deviceDidRemove(device: device) }
}

private func hidInputReport(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context, result == kIOReturnSuccess, reportLength > 0 else { return }
    let monitor = Unmanaged<HIDRemoteMonitor>.fromOpaque(context).takeUnretainedValue()
    let data = Data(bytes: report, count: reportLength)
    DispatchQueue.main.async {
        monitor.handleReport(reportID: reportID, data: data)
    }
}

final class HIDRemoteMonitor {
    private let settings: AppSettings
    private let eventSuppressor = KeyboardEventSuppressor()
    private var manager: IOHIDManager?
    private var activeDevices: [IOHIDDevice] = []
    private var activeDeviceIsSeized = false
    private var activeUsages = Set<UInt16>()
    private var repeatTimers: [UInt16: DispatchSourceTimer] = [:]
    private var permissionMonitor: DispatchSourceTimer?
    private(set) var status = "按键映射未启用"
    var onStatus: ((String) -> Void)?

    /// Event Tap 是否已挂起（拦截 F5 / 映射键）。
    var isEventTapRunning: Bool { eventSuppressor.isRunning }
    /// IOHIDManager 是否已打开。
    var isManagerOpen: Bool { manager != nil }
    /// 是否已独占至少一个 RC003 HID 接口。
    var hasSeizedDevice: Bool { activeDeviceIsSeized && !activeDevices.isEmpty }

    init(settings: AppSettings) {
        self.settings = settings
    }

    static var inputMonitoringAccess: IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    }

    static var isInputMonitoringGranted: Bool {
        inputMonitoringAccess == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    private var needsHIDSession: Bool {
        // 始终拦截麦克风 F5；自定义映射可选
        true
    }

    func start() {
        // 重启时不要先 stop() 整段关掉 mic_block，否则重试窗口期间 F5 会漏进 Cursor。
        tearDownHIDSession(keepingEventTap: true)

        guard needsHIDSession else {
            eventSuppressor.setBlockRemoteMicHardwareKey(false)
            eventSuppressor.stop()
            updateStatus("按键由 macOS 原生处理")
            return
        }

        let inputGranted = Self.isInputMonitoringGranted
        let accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
        let wantMicBlock = true
        let wantMapping = settings.customMappingEnabled
        AppLogger.shared.write(
            "HID PERMISSIONS input=\(inputGranted) accessibility=\(accessibilityGranted) " +
                "micBlock=\(wantMicBlock) mapping=\(wantMapping)"
        )

        if !inputGranted {
            _ = Self.requestInputMonitoringAccess()
            updateStatus("需要输入监控权限（拦截麦克风键 / 读取遥控器）")
        }
        if !accessibilityGranted {
            _ = KeyboardInjector.requestAccessibilityAccess()
        }

        let suppressionReady = eventSuppressor.isRunning || eventSuppressor.start()
        eventSuppressor.setBlockRemoteMicHardwareKey(wantMicBlock)
        AppLogger.shared.write(
            "HID FILTER ready=\(suppressionReady) mic_block=\(wantMicBlock)"
        )
        if !suppressionReady {
            updateStatus("麦克风键拦截失败：请给本应用打开「辅助功能」和「输入监控」后重启")
            AppLogger.shared.write("HID FILTER event_tap_failed")
        }

        if wantMapping && (!inputGranted || !accessibilityGranted) {
            updateStatus("麦克风拦截已尝试；按键映射还需辅助功能+输入监控")
        }

        let hidIdentity = VoiceBridgeDeviceProfiles.xiaomiRC003.hidIdentity
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [
            kIOHIDVendorIDKey as String: hidIdentity.vendorID,
            kIOHIDProductIDKey as String: hidIdentity.productID,
        ] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, hidInputReport, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            updateStatus(
                suppressionReady
                    ? "HID 打开失败，仍用 Event Tap 拦截麦克风键"
                    : "无法读取遥控器且无法拦截麦克风键"
            )
            AppLogger.shared.write("HID MANAGER OPEN FAILED \(result)")
            return
        }
        self.manager = manager
        startPermissionMonitor()
        updateStatus(
            wantMapping
                ? "等待 RC003（听写拦截 F5 + 按键映射）"
                : "等待 RC003（系统听写：拦截麦克风 F5）"
        )
        AppLogger.shared.write("HID START mode=speech_only")
    }

    func applyVoiceMicPolicy() {
        if manager == nil || !eventSuppressor.isRunning {
            start()
            return
        }
        if !eventSuppressor.isRunning {
            _ = eventSuppressor.start()
        }
        eventSuppressor.setBlockRemoteMicHardwareKey(true)
    }

    func stop() {
        tearDownHIDSession(keepingEventTap: false)
    }

    private func tearDownHIDSession(keepingEventTap: Bool) {
        permissionMonitor?.cancel()
        permissionMonitor = nil
        repeatTimers.values.forEach { $0.cancel() }
        repeatTimers.removeAll()
        activeUsages.removeAll()
        if !keepingEventTap {
            eventSuppressor.setBlockRemoteMicHardwareKey(false)
            eventSuppressor.stop()
        }
        for device in activeDevices {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        activeDevices.removeAll()
        activeDeviceIsSeized = false
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    fileprivate func deviceDidMatch(result: IOReturn, device: IOHIDDevice) {
        guard result == kIOReturnSuccess else {
            updateStatus("RC003 HID 打开失败")
            return
        }
        // 可能有多个 HID 接口（按键集合 + 键盘 F5）；全部尝试独占
        if activeDevices.contains(where: { CFEqual($0, device) }) { return }

        let seizeResult = IOHIDDeviceOpen(
            device,
            IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        )
        if seizeResult == kIOReturnSuccess {
            activeDevices.append(device)
            activeDeviceIsSeized = true
            updateStatus("RC003 按键映射已连接（独占×\(activeDevices.count)）")
            AppLogger.shared.write("HID CONNECTED mode=seized count=\(activeDevices.count)")
            return
        }

        let monitorResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard monitorResult == kIOReturnSuccess else {
            AppLogger.shared.write(
                "HID DEVICE OPEN FAILED seize=\(seizeResult) monitor=\(monitorResult)"
            )
            if activeDevices.isEmpty {
                updateStatus("无法读取 RC003（错误 \(monitorResult)）")
            }
            return
        }

        activeDevices.append(device)
        if !activeDeviceIsSeized {
            activeDeviceIsSeized = false
        }
        let suffix = eventSuppressor.isRunning ? "兼容模式" : "兼容模式；系统原动作可能保留"
        updateStatus("RC003 按键映射已连接（\(suffix)×\(activeDevices.count)）")
        AppLogger.shared.write(
            "HID CONNECTED mode=monitored seize_error=\(seizeResult) count=\(activeDevices.count)"
        )
    }

    fileprivate func deviceDidRemove(device: IOHIDDevice) {
        guard let index = activeDevices.firstIndex(where: { CFEqual($0, device) }) else { return }
        IOHIDDeviceClose(activeDevices[index], IOOptionBits(kIOHIDOptionsTypeNone))
        activeDevices.remove(at: index)
        if activeDevices.isEmpty {
            activeDeviceIsSeized = false
            activeUsages.removeAll()
            repeatTimers.values.forEach { $0.cancel() }
            repeatTimers.removeAll()
            updateStatus("RC003 按键设备已断开")
            AppLogger.shared.write("HID DISCONNECTED")
        } else {
            updateStatus("RC003 仍连接 \(activeDevices.count) 个 HID 接口")
        }
    }

    fileprivate func handleReport(reportID: UInt32, data: Data) {
        guard manager != nil else { return }
        guard let usages = RemoteHIDReportParser.usages(reportID: reportID, data: data) else {
            return
        }
        let pressed = usages.subtracting(activeUsages)
        let released = activeUsages.subtracting(usages)
        activeUsages = usages

        // 麦克风 usage 0x3E：仅拦截，不参与按键映射
        let micUsage: UInt16 = 0x3E
        if pressed.contains(micUsage) || released.contains(micUsage) {
            AppLogger.shared.write("HID MIC edge suppressed (system speech / voice key)")
        }

        guard settings.customMappingEnabled else { return }
        guard runtimePermissionsAreValid() else {
            releaseForRevokedPermissions()
            return
        }

        for usage in pressed.sorted() {
            guard usage != micUsage, let button = RemoteButton.usageMap[usage] else { continue }
            let action = settings.action(for: button)
            if !activeDeviceIsSeized {
                eventSuppressor.arm(button: button, edge: .down)
            }
            if !KeyboardInjector.send(action) {
                stop()
                updateStatus("辅助功能权限已失效；已释放遥控器")
                return
            }
            startRepeatIfNeeded(usage: usage, button: button, action: action)
            AppLogger.shared.write("HID BUTTON down=\(button.rawValue) action=\(action.displayName)")
        }

        for usage in released {
            guard usage != micUsage else { continue }
            if !activeDeviceIsSeized, let button = RemoteButton.usageMap[usage] {
                eventSuppressor.arm(button: button, edge: .up)
            }
            repeatTimers.removeValue(forKey: usage)?.cancel()
        }
    }

    private func startRepeatIfNeeded(
        usage: UInt16,
        button: RemoteButton,
        action: ButtonAction
    ) {
        let repeatable: Set<RemoteButton> = [
            .up, .down, .left, .right, .back, .volumeUp, .volumeDown,
        ]
        guard repeatable.contains(button), !action.suppressesKeyRepeat else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval: DispatchTimeInterval = button == .back ? .milliseconds(50) : .milliseconds(100)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.activeUsages.contains(usage) else { return }
            guard self.runtimePermissionsAreValid() else {
                self.releaseForRevokedPermissions()
                return
            }
            if !self.activeDeviceIsSeized {
                self.eventSuppressor.arm(button: button, edge: .down)
            }
            if !KeyboardInjector.send(action) {
                self.releaseForRevokedPermissions()
            }
        }
        repeatTimers[usage] = timer
        timer.resume()
    }

    private func runtimePermissionsAreValid() -> Bool {
        guard Self.inputMonitoringAccess == kIOHIDAccessTypeGranted else { return false }
        if settings.customMappingEnabled {
            return KeyboardInjector.isAccessibilityTrusted
        }
        return true
    }

    private func startPermissionMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.manager != nil else { return }
            if !self.runtimePermissionsAreValid() {
                self.releaseForRevokedPermissions()
            }
        }
        permissionMonitor = timer
        timer.resume()
    }

    private func releaseForRevokedPermissions() {
        stop()
        updateStatus("系统权限已失效；已释放遥控器")
        AppLogger.shared.write("HID RELEASED permission_revoked")
    }

    private func updateStatus(_ value: String) {
        status = value
        onStatus?(value)
    }
}
