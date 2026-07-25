import Foundation

private let defaultsSuiteName = "com.jiamid.MiControlApp"
private let settingsChangedNotification = Notification.Name("com.jiamid.MiControlApp.settingsChanged")

private enum RemoteButton: String, CaseIterable, Codable {
    case power
    case up
    case left
    case ok
    case right
    case down
    case back
    case volumeUp = "volume_up"
    case home
    case volumeDown = "volume_down"
    case menu
    case tv
}

private enum CodexRemoteAction: String, Codable, CaseIterable {
    case activate
    case submit
    case stop
    case commandPalette
    case newTask
}

private struct MacroStep: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
}

private enum ButtonAction: Codable, Equatable {
    case disabled
    case escape
    case returnKey
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case deleteBackward
    case showDesktop
    case contextMenu
    case appSwitcher
    case volumeUp
    case volumeDown
    case volumeMute
    case playPause
    case custom(keyCode: UInt16, modifiers: UInt64)
    case macro([MacroStep])
    case openApp(bundleID: String)
    case codex(CodexRemoteAction)

    private var presetRawValue: String? {
        switch self {
        case .disabled: return "disabled"
        case .escape: return "escape"
        case .returnKey: return "returnKey"
        case .arrowUp: return "arrowUp"
        case .arrowDown: return "arrowDown"
        case .arrowLeft: return "arrowLeft"
        case .arrowRight: return "arrowRight"
        case .deleteBackward: return "deleteBackward"
        case .showDesktop: return "showDesktop"
        case .contextMenu: return "contextMenu"
        case .appSwitcher: return "appSwitcher"
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        case .volumeMute: return "volumeMute"
        case .playPause: return "playPause"
        case .custom, .macro, .openApp, .codex: return nil
        }
    }

    var displayName: String {
        switch self {
        case .disabled: return "disabled"
        case .escape: return "escape"
        case .returnKey: return "returnKey"
        case .arrowUp: return "arrowUp"
        case .arrowDown: return "arrowDown"
        case .arrowLeft: return "arrowLeft"
        case .arrowRight: return "arrowRight"
        case .deleteBackward: return "deleteBackward"
        case .showDesktop: return "showDesktop"
        case .contextMenu: return "contextMenu"
        case .appSwitcher: return "appSwitcher"
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        case .volumeMute: return "volumeMute"
        case .playPause: return "playPause"
        case let .custom(keyCode, modifiers): return "custom(\(keyCode),\(modifiers))"
        case let .macro(steps): return "macro(\(steps.count) steps)"
        case let .openApp(bundleID): return "openApp(\(bundleID))"
        case let .codex(action): return "codex:\(action.rawValue)"
        }
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch raw {
            case "disabled": self = .disabled
            case "escape": self = .escape
            case "returnKey": self = .returnKey
            case "arrowUp": self = .arrowUp
            case "arrowDown": self = .arrowDown
            case "arrowLeft": self = .arrowLeft
            case "arrowRight": self = .arrowRight
            case "deleteBackward": self = .deleteBackward
            case "showDesktop": self = .showDesktop
            case "contextMenu": self = .contextMenu
            case "appSwitcher": self = .appSwitcher
            case "volumeUp": self = .volumeUp
            case "volumeDown": self = .volumeDown
            case "volumeMute": self = .volumeMute
            case "playPause": self = .playPause
            default: throw CLIError.invalidAction(raw)
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "custom":
            self = .custom(
                keyCode: try container.decode(UInt16.self, forKey: .keyCode),
                modifiers: try container.decode(UInt64.self, forKey: .modifiers)
            )
        case "macro":
            self = .macro(try container.decode([MacroStep].self, forKey: .steps))
        case "openApp":
            self = .openApp(bundleID: try container.decode(String.self, forKey: .bundleID))
        case "codex":
            self = .codex(try container.decode(CodexRemoteAction.self, forKey: .action))
        default:
            throw CLIError.invalidAction(kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        if let raw = presetRawValue {
            var single = encoder.singleValueContainer()
            try single.encode(raw)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .custom(keyCode, modifiers):
            try container.encode("custom", forKey: .kind)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers, forKey: .modifiers)
        case let .macro(steps):
            try container.encode("macro", forKey: .kind)
            try container.encode(steps, forKey: .steps)
        case let .openApp(bundleID):
            try container.encode("openApp", forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
        case let .codex(action):
            try container.encode("codex", forKey: .kind)
            try container.encode(action, forKey: .action)
        default:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case keyCode
        case modifiers
        case steps
        case bundleID
        case action
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case invalidButton(String)
    case invalidAction(String)
    case invalidSpeechDestination(String)

    var description: String {
        switch self {
        case .usage: return usageText
        case .invalidButton(let value): return "Invalid button: \(value)"
        case .invalidAction(let value): return "Invalid action: \(value)"
        case .invalidSpeechDestination(let value): return "Invalid speech destination: \(value)"
        }
    }
}

private let usageText = """
Usage:
  MiControlCLI status
  MiControlCLI enable-mapping <true|false>
  MiControlCLI set <button> <action>
  MiControlCLI speech <frontmost|codex-draft>
  MiControlCLI reset

Buttons:
  \(RemoteButton.allCases.map(\.rawValue).joined(separator: ", "))

Actions:
  disabled, escape, returnKey, arrowUp, arrowDown, arrowLeft, arrowRight,
  deleteBackward, showDesktop, contextMenu, appSwitcher, volumeUp, volumeDown,
  volumeMute, playPause, openApp:<bundle-id>,
  codex:activate, codex:submit, codex:stop, codex:commandPalette, codex:newTask
"""

private let defaultBindings: [RemoteButton: ButtonAction] = [
    .power: .escape,
    .up: .arrowUp,
    .left: .arrowLeft,
    .ok: .returnKey,
    .right: .arrowRight,
    .down: .arrowDown,
    .back: .deleteBackward,
    .volumeUp: .volumeUp,
    .home: .showDesktop,
    .volumeDown: .volumeDown,
    .menu: .contextMenu,
    .tv: .appSwitcher,
]

private let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
private let arguments = Array(CommandLine.arguments.dropFirst())

private func loadBindings() -> [RemoteButton: ButtonAction] {
    guard let data = defaults.data(forKey: "buttonBindings"),
          let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data)
    else { return defaultBindings }
    return defaultBindings.merging(
        Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            RemoteButton(rawValue: key).map { ($0, value) }
        })
    ) { _, saved in saved }
}

private func saveBindings(_ bindings: [RemoteButton: ButtonAction]) throws {
    let raw = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
    let data = try JSONEncoder().encode(raw)
    defaults.set(data, forKey: "buttonBindings")
    defaults.synchronize()
    notifySettingsChanged()
}

private func notifySettingsChanged() {
    DistributedNotificationCenter.default().postNotificationName(
        settingsChangedNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
}

private func parseBool(_ value: String) throws -> Bool {
    switch value.lowercased() {
    case "true", "1", "yes", "on": return true
    case "false", "0", "no", "off": return false
    default: throw CLIError.usage
    }
}

private func parseAction(_ value: String) throws -> ButtonAction {
    switch value {
    case "disabled": return .disabled
    case "escape": return .escape
    case "returnKey": return .returnKey
    case "arrowUp": return .arrowUp
    case "arrowDown": return .arrowDown
    case "arrowLeft": return .arrowLeft
    case "arrowRight": return .arrowRight
    case "deleteBackward": return .deleteBackward
    case "showDesktop": return .showDesktop
    case "contextMenu": return .contextMenu
    case "appSwitcher": return .appSwitcher
    case "volumeUp": return .volumeUp
    case "volumeDown": return .volumeDown
    case "volumeMute": return .volumeMute
    case "playPause": return .playPause
    default:
        if value.hasPrefix("openApp:") {
            return .openApp(bundleID: String(value.dropFirst("openApp:".count)))
        }
        if value.hasPrefix("codex:") {
            let raw = String(value.dropFirst("codex:".count))
            guard let action = CodexRemoteAction(rawValue: raw) else {
                throw CLIError.invalidAction(value)
            }
            return .codex(action)
        }
        throw CLIError.invalidAction(value)
    }
}

private func printStatus() {
    let mappingEnabled = defaults.object(forKey: "customMappingEnabled") != nil
        ? defaults.bool(forKey: "customMappingEnabled")
        : defaults.bool(forKey: "exclusiveHID")
    let speechDestination = defaults.string(forKey: "speechDestination") ?? "frontmost"
    print("customMappingEnabled: \(mappingEnabled)")
    print("speechDestination: \(speechDestination)")
    print("buttonBindings:")
    for button in RemoteButton.allCases {
        print("  \(button.rawValue): \(loadBindings()[button]?.displayName ?? "disabled")")
    }
}

do {
    guard let command = arguments.first else { throw CLIError.usage }
    switch command {
    case "status":
        guard arguments.count == 1 else { throw CLIError.usage }
        printStatus()
    case "enable-mapping":
        guard arguments.count == 2 else { throw CLIError.usage }
        defaults.set(try parseBool(arguments[1]), forKey: "customMappingEnabled")
        defaults.synchronize()
        notifySettingsChanged()
    case "set":
        guard arguments.count == 3 else { throw CLIError.usage }
        guard let button = RemoteButton(rawValue: arguments[1]) else {
            throw CLIError.invalidButton(arguments[1])
        }
        var bindings = loadBindings()
        bindings[button] = try parseAction(arguments[2])
        try saveBindings(bindings)
    case "speech":
        guard arguments.count == 2 else { throw CLIError.usage }
        let raw: String
        switch arguments[1] {
        case "frontmost": raw = "frontmost"
        case "codex-draft": raw = "codexDraft"
        default: throw CLIError.invalidSpeechDestination(arguments[1])
        }
        defaults.set(raw, forKey: "speechDestination")
        defaults.synchronize()
        notifySettingsChanged()
    case "reset":
        guard arguments.count == 1 else { throw CLIError.usage }
        try saveBindings(defaultBindings)
    default:
        throw CLIError.usage
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(2)
}
