import Combine
import Foundation

enum SpeechDestination: String, CaseIterable, Identifiable {
    case frontmost
    case codexDraft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frontmost: return "当前输入框"
        case .codexDraft: return "Codex 草稿"
        }
    }
}

final class AppSettings: ObservableObject {
    static let defaultsSuiteName = "com.jiamid.MiControlApp"
    static let settingsChangedNotification = Notification.Name("com.jiamid.MiControlApp.settingsChanged")

    private enum Keys {
        static let customMappingEnabled = "customMappingEnabled"
        static let legacyExclusiveHID = "exclusiveHID"
        static let buttonBindings = "buttonBindings"
        static let peripheralIdentifier = "peripheralIdentifier"
        static let speechLocale = "speechLocale"
        static let speechDestination = "speechDestination"
    }

    private let defaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?

    @Published var customMappingEnabled: Bool {
        didSet { defaults.set(customMappingEnabled, forKey: Keys.customMappingEnabled) }
    }

    @Published var speechLocale: String {
        didSet { defaults.set(speechLocale, forKey: Keys.speechLocale) }
    }

    @Published var speechDestination: SpeechDestination {
        didSet { defaults.set(speechDestination.rawValue, forKey: Keys.speechDestination) }
    }

    @Published var buttonBindings: [RemoteButton: ButtonAction] {
        didSet { saveBindings() }
    }

    var peripheralIdentifier: UUID? {
        get {
            guard let raw = defaults.string(forKey: Keys.peripheralIdentifier) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.peripheralIdentifier)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.customMappingEnabled) != nil {
            customMappingEnabled = defaults.bool(forKey: Keys.customMappingEnabled)
        } else {
            customMappingEnabled = defaults.bool(forKey: Keys.legacyExclusiveHID)
        }
        speechLocale = defaults.string(forKey: Keys.speechLocale) ?? "zh-CN"
        speechDestination = defaults.string(forKey: Keys.speechDestination)
            .flatMap(SpeechDestination.init(rawValue:)) ?? .frontmost

        if
            let data = defaults.data(forKey: Keys.buttonBindings),
            let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data)
        {
            buttonBindings = Self.defaultBindings.merging(
                Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    RemoteButton(rawValue: key).map { ($0, value) }
                })
            ) { _, saved in saved }
        } else {
            buttonBindings = Self.defaultBindings
        }

        defaultsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.settingsChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromDefaults()
        }
    }

    deinit {
        if let defaultsObserver {
            DistributedNotificationCenter.default().removeObserver(defaultsObserver)
        }
    }

    func action(for button: RemoteButton) -> ButtonAction {
        buttonBindings[button] ?? .disabled
    }

    func setAction(_ action: ButtonAction, for button: RemoteButton) {
        buttonBindings[button] = action
    }

    func resetBindings() {
        buttonBindings = Self.defaultBindings
    }

    private func saveBindings() {
        let raw = Dictionary(uniqueKeysWithValues: buttonBindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.buttonBindings)
        }
    }

    private func reloadFromDefaults() {
        if defaults.object(forKey: Keys.customMappingEnabled) != nil {
            customMappingEnabled = defaults.bool(forKey: Keys.customMappingEnabled)
        }
        speechLocale = defaults.string(forKey: Keys.speechLocale) ?? "zh-CN"
        speechDestination = defaults.string(forKey: Keys.speechDestination)
            .flatMap(SpeechDestination.init(rawValue:)) ?? .frontmost
        if
            let data = defaults.data(forKey: Keys.buttonBindings),
            let decoded = try? JSONDecoder().decode([String: ButtonAction].self, from: data)
        {
            buttonBindings = Self.defaultBindings.merging(
                Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                    RemoteButton(rawValue: key).map { ($0, value) }
                })
            ) { _, saved in saved }
        }
    }

    static let defaultBindings: [RemoteButton: ButtonAction] = [
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
}
