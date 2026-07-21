import AppKit
import Combine
import Foundation

/// 设置页里录制单键 / 短宏；用引用类型避免 SwiftUI View 值捕获导致状态丢失。
final class KeyRecordingController: ObservableObject {
    @Published private(set) var button: RemoteButton?
    @Published private(set) var isMacro = false
    @Published private(set) var draft: [MacroStep] = []

    private var monitor: Any?

    var isRecording: Bool { button != nil }

    func isRecording(_ button: RemoteButton) -> Bool {
        self.button == button
    }

    func begin(for button: RemoteButton, asMacro: Bool, settings: AppSettings) {
        stop(save: false, settings: nil)
        self.button = button
        self.isMacro = asMacro
        self.draft = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event: event, settings: settings)
            }
            return nil
        }
    }

    func undoLastStep() {
        guard isMacro, !draft.isEmpty else { return }
        draft.removeLast()
    }

    func finish(settings: AppSettings) {
        guard let button, isMacro, !draft.isEmpty else {
            stop(save: false, settings: nil)
            return
        }
        settings.setAction(.macro(draft), for: button)
        stop(save: false, settings: nil)
    }

    func cancel() {
        stop(save: false, settings: nil)
    }

    private func handle(event: NSEvent, settings: AppSettings) {
        guard let button else { return }
        let keyCode = UInt16(event.keyCode)
        let modifierOnly: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierOnly.contains(keyCode) { return }
        if keyCode == 53 {
            cancel()
            return
        }

        let modifiers = KeyChordFormatter.normalizedModifiers(from: event.modifierFlags)
        let step = MacroStep(keyCode: keyCode, modifiers: modifiers)

        if isMacro {
            guard draft.count < ButtonAction.macroStepLimit else { return }
            draft.append(step)
            if draft.count >= ButtonAction.macroStepLimit {
                finish(settings: settings)
            }
        } else {
            settings.setAction(.custom(keyCode: keyCode, modifiers: modifiers), for: button)
            stop(save: false, settings: nil)
        }
    }

    private func stop(save: Bool, settings: AppSettings?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        button = nil
        isMacro = false
        draft = []
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
