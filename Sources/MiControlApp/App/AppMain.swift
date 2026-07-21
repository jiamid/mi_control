import AppKit
import Combine
import Darwin
import SwiftUI

@main
enum MiControlAppMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = BridgeAppModel()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var subscriptions = Set<AnyCancellable>()
    private var terminationSignalSources: [DispatchSourceSignal] = []

    private let connectionItem = NSMenuItem(title: "正在初始化蓝牙", action: nil, keyEquivalent: "")
    private let batteryItem = NSMenuItem(title: "电量：—", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignalHandlers()
        configureStatusItem()
        observeModel()
        model.startIfNeeded()
        refreshMenuStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        terminationSignalSources.forEach { $0.cancel() }
        terminationSignalSources.removeAll()
    }

    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStatus()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.toolTip = "MiControlApp"
            button.image = statusBarImage(streaming: false)
            if button.image == nil {
                button.title = "Mi"
            }
        }

        connectionItem.isEnabled = false
        batteryItem.isEnabled = false

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(connectionItem)
        menu.addItem(batteryItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("打开设置", action: #selector(showSettings)))
        menu.addItem(menuItem("退出", action: #selector(quit)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func observeModel() {
        Publishers.CombineLatest3(
            model.$connectionStatus,
            model.$isStreaming,
            model.$batteryPercent
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenuStatus()
            }
            .store(in: &subscriptions)
    }

    private func refreshMenuStatus() {
        connectionItem.title = "连接状态：\(model.connectionStatus)"
        if let percent = model.batteryPercent {
            batteryItem.title = "电量：\(percent)%"
            batteryItem.isHidden = false
        } else {
            batteryItem.title = "电量：未获取"
            batteryItem.isHidden = false
        }
        statusItem?.button?.image = statusBarImage(streaming: model.isStreaming)
    }

    /// 优先用遥控器 SF Symbol；听写中用实心版提示状态。
    private func statusBarImage(streaming: Bool) -> NSImage? {
        let candidates = streaming
            ? ["tv.remote.fill", "tv.remote", "appletvremote.gen4.fill", "appletvremote.gen4"]
            : ["tv.remote", "appletvremote.gen4", "appletvremote.gen3", "appletvremote.gen2"]
        let description = streaming ? "MiControlApp 语音中" : "MiControlApp"
        for name in candidates {
            guard var image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: description
            ) else { continue }
            if let configured = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            ) {
                image = configured
            }
            image.isTemplate = true
            return image
        }
        return NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: description
        ).map {
            $0.isTemplate = true
            return $0
        }
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        guard let windowController = settingsWindowController,
              let window = windowController.window else { return }
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindowController() -> NSWindowController {
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiControlApp"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 620)
        window.setFrameAutosaveName("MiControlAppSettings")
        window.center()
        return NSWindowController(window: window)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
