import Foundation

enum RemoteButton: String, CaseIterable, Codable, Identifiable {
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

    var id: String { rawValue }

    var hidUsage: UInt16 {
        switch self {
        case .power: return 0x66
        case .up: return 0x52
        case .left: return 0x50
        case .ok: return 0x28
        case .right: return 0x4F
        case .down: return 0x51
        case .back: return 0xF1
        case .volumeUp: return 0x80
        case .home: return 0x4A
        case .volumeDown: return 0x81
        case .menu: return 0x65
        case .tv: return 0x35
        }
    }

    var shortLabel: String {
        switch self {
        case .power: return "电源"
        case .up: return "上"
        case .left: return "左"
        case .ok: return "OK"
        case .right: return "右"
        case .down: return "下"
        case .back: return "返回"
        case .volumeUp: return "+"
        case .home: return "主页"
        case .volumeDown: return "−"
        case .menu: return "菜单"
        case .tv: return "TV"
        }
    }

    var displayName: String {
        switch self {
        case .power: return "电源键"
        case .up: return "上键"
        case .left: return "左键"
        case .ok: return "确定键"
        case .right: return "右键"
        case .down: return "下键"
        case .back: return "返回键"
        case .volumeUp: return "音量 +"
        case .home: return "主页键"
        case .volumeDown: return "音量 -"
        case .menu: return "菜单键"
        case .tv: return "TV 键"
        }
    }

    static let usageMap = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.hidUsage, $0) }
    )

    var nativeEvent: RemoteNativeEvent? {
        switch self {
        case .ok: return .keyboard(keyCode: 36)
        case .tv: return .keyboard(keyCode: 50)
        case .home: return .keyboard(keyCode: 115)
        case .right: return .keyboard(keyCode: 124)
        case .left: return .keyboard(keyCode: 123)
        case .down: return .keyboard(keyCode: 125)
        case .up: return .keyboard(keyCode: 126)
        case .menu: return .keyboard(keyCode: 110)
        case .power: return .systemKey(type: 6)
        case .volumeUp: return .systemKey(type: 0)
        case .volumeDown: return .systemKey(type: 1)
        case .back: return nil
        }
    }
}

enum RemoteNativeEvent: Equatable {
    case keyboard(keyCode: UInt16)
    case systemKey(type: Int32)
}

enum RemoteEventEdge: Equatable {
    case down
    case up
}
