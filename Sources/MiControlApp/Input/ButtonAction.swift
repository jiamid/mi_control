import AppKit
import Foundation

/// 宏里的一步：修饰键 + 单个按键。
struct MacroStep: Equatable, Hashable, Codable {
    var keyCode: UInt16
    var modifiers: UInt64

    var displayName: String {
        KeyChordFormatter.displayName(keyCode: keyCode, modifiers: modifiers)
    }
}

/// 遥控器按键映射目标。支持旧预设、单键自定义，以及短宏（按键序列）。
enum ButtonAction: Equatable, Hashable, Codable, Identifiable {
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
    /// 自定义：单个 keyCode + CGEventFlags 风格修饰键
    case custom(keyCode: UInt16, modifiers: UInt64)
    /// 短宏：按顺序发送多步按键（最多 8 步）
    case macro([MacroStep])
    /// 打开指定 App（按 Bundle Identifier）
    case openApp(bundleID: String)

    static let macroStepLimit = 8

    var id: String {
        switch self {
        case .custom(let keyCode, let modifiers):
            return "custom:\(keyCode):\(modifiers)"
        case .macro(let steps):
            return "macro:" + steps.map { "\($0.keyCode)-\($0.modifiers)" }.joined(separator: ".")
        case .openApp(let bundleID):
            return "openApp:\(bundleID)"
        default:
            return presetRawValue ?? "unknown"
        }
    }

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
        case .custom, .macro, .openApp: return nil
        }
    }

    /// 设置页下拉用的预设列表（不含自定义）。
    static var presetCases: [ButtonAction] {
        [
            .disabled,
            .escape,
            .returnKey,
            .arrowUp,
            .arrowDown,
            .arrowLeft,
            .arrowRight,
            .deleteBackward,
            .showDesktop,
            .contextMenu,
            .appSwitcher,
            .volumeUp,
            .volumeDown,
            .volumeMute,
            .playPause,
        ]
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var isMacro: Bool {
        if case .macro = self { return true }
        return false
    }

    var isOpenApp: Bool {
        if case .openApp = self { return true }
        return false
    }

    /// 可「重录」的用户动作（单键或宏）
    var isUserRecorded: Bool { isCustom || isMacro }

    var isDisabled: Bool {
        if case .disabled = self { return true }
        return false
    }

    /// 长按时不应连续触发的动作。
    var suppressesKeyRepeat: Bool { isDisabled || isMacro || isOpenApp }

    var displayName: String {
        switch self {
        case .disabled: return "禁用"
        case .escape: return "Escape"
        case .returnKey: return "Return"
        case .arrowUp: return "方向上"
        case .arrowDown: return "方向下"
        case .arrowLeft: return "方向左"
        case .arrowRight: return "方向右"
        case .deleteBackward: return "Delete（退格）"
        case .showDesktop: return "显示桌面"
        case .contextMenu: return "Shift-F10"
        case .appSwitcher: return "Command-Tab"
        case .volumeUp: return "系统音量 +"
        case .volumeDown: return "系统音量 -"
        case .volumeMute: return "系统静音"
        case .playPause: return "播放 / 暂停"
        case let .custom(keyCode, modifiers):
            return KeyChordFormatter.displayName(keyCode: keyCode, modifiers: modifiers)
        case let .macro(steps):
            if steps.isEmpty { return "空宏" }
            let joined = steps.map(\.displayName).joined(separator: " → ")
            return steps.count > 1 ? "宏·\(joined)" : joined
        case let .openApp(bundleID):
            return "打开 \(Self.appDisplayName(bundleID: bundleID))"
        }
    }

    static func appDisplayName(bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url)
        else {
            return bundleID
        }
        if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !display.isEmpty
        {
            return display
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty
        {
            return name
        }
        return bundleID
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self)
        {
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
            default:
                throw DecodingError.dataCorruptedError(
                    in: single,
                    debugDescription: "Unknown ButtonAction \(raw)"
                )
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "custom":
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decode(UInt64.self, forKey: .modifiers)
            self = .custom(keyCode: keyCode, modifiers: modifiers)
        case "macro":
            var steps = try container.decode([MacroStep].self, forKey: .steps)
            if steps.count > Self.macroStepLimit {
                steps = Array(steps.prefix(Self.macroStepLimit))
            }
            self = .macro(steps)
        case "openApp":
            let bundleID = try container.decode(String.self, forKey: .bundleID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .bundleID,
                    in: container,
                    debugDescription: "openApp requires a non-empty bundleID"
                )
            }
            self = .openApp(bundleID: bundleID)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown ButtonAction kind \(kind)"
            )
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
            try container.encode(Array(steps.prefix(Self.macroStepLimit)), forKey: .steps)
        case let .openApp(bundleID):
            try container.encode("openApp", forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
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
    }
}
