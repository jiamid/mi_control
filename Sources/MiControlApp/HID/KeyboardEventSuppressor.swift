import AppKit
import CoreGraphics
import Foundation

private func keyboardEventSuppressorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let suppressor = Unmanaged<KeyboardEventSuppressor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return suppressor.handle(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

final class KeyboardEventSuppressor {
    private static let systemDefinedEventTypeRawValue: UInt32 = 14
    /// RC003 麦克风硬件键 = F5（hid usage 0x3E / keycode 96）
    static let remoteMicKeyCode: UInt16 = 96

    private struct PendingEvent {
        let event: RemoteNativeEvent
        let edge: RemoteEventEdge
        let expiresAt: TimeInterval
    }

    private let lock = NSLock()
    private var pendingEvents: [PendingEvent] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// 系统听写模式：永久拦截遥控器麦克风 F5，避免漏进 Cursor 打开顶部搜索等
    private var blockRemoteMicHardwareKey = false

    private(set) var isRunning = false

    func setBlockRemoteMicHardwareKey(_ enabled: Bool) {
        lock.lock()
        blockRemoteMicHardwareKey = enabled
        lock.unlock()
        AppLogger.shared.write("HID FILTER mic_block=\(enabled)")
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << Self.systemDefinedEventTypeRawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Prefer HID tap (earlier) so F5 never reaches Cursor; fall back to session tap.
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        var created: CFMachPort?
        for location in locations {
            if let eventTap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: keyboardEventSuppressorCallback,
                userInfo: context
            ) {
                created = eventTap
                AppLogger.shared.write(
                    "HID FILTER tap_location=\(location == .cghidEventTap ? "hid" : "session")"
                )
                break
            }
        }
        guard let eventTap = created else {
            return false
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        lock.lock()
        pendingEvents.removeAll()
        lock.unlock()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    func arm(button: RemoteButton, edge: RemoteEventEdge) {
        guard let nativeEvent = button.nativeEvent else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        pendingEvents.removeAll { $0.expiresAt <= now }
        pendingEvents.append(PendingEvent(
            event: nativeEvent,
            edge: edge,
            expiresAt: now + 0.18
        ))
        if pendingEvents.count > 32 {
            pendingEvents.removeFirst(pendingEvents.count - 32)
        }
        lock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardInjector.syntheticEventMarker {
            return false
        }
        guard let descriptor = descriptor(type: type, event: event) else { return false }

        // 永久拦截遥控器麦克风 F5，防止 Cursor / 其它 App 把 F5 当成快捷键
        if case let .keyboard(code) = descriptor.event, code == Self.remoteMicKeyCode {
            lock.lock()
            let blockMic = blockRemoteMicHardwareKey
            lock.unlock()
            if blockMic {
                return true
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        pendingEvents.removeAll { $0.expiresAt <= now }
        guard let matchIndex = pendingEvents.firstIndex(where: {
            $0.event == descriptor.event && $0.edge == descriptor.edge
        }) else {
            lock.unlock()
            return false
        }
        pendingEvents.remove(at: matchIndex)
        lock.unlock()
        return true
    }

    private func descriptor(
        type: CGEventType,
        event: CGEvent
    ) -> (event: RemoteNativeEvent, edge: RemoteEventEdge)? {
        if type.rawValue == Self.systemDefinedEventTypeRawValue {
            guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
            let systemKeyType = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
            let keyState = (nsEvent.data1 & 0x0000_FF00) >> 8
            let edge: RemoteEventEdge
            switch keyState {
            case 0xA: edge = .down
            case 0xB: edge = .up
            default: return nil
            }
            return (.systemKey(type: systemKeyType), edge)
        }

        switch type {
        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            return (.keyboard(keyCode: keyCode), type == .keyDown ? .down : .up)
        default:
            return nil
        }
    }
}
