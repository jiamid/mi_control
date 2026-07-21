import Foundation

struct VoiceBridgeHIDIdentity: Equatable {
    let vendorID: Int
    let productID: Int
}

/// 仅支持小米 RC003。
struct VoiceBridgeDeviceProfile: Equatable {
    let id: String
    let displayName: String
    let manufacturer: String
    let model: String
    let bluetoothNames: Set<String>
    let hidIdentity: VoiceBridgeHIDIdentity

    init(
        id: String,
        displayName: String,
        manufacturer: String,
        model: String,
        bluetoothNames: Set<String>,
        hidIdentity: VoiceBridgeHIDIdentity
    ) {
        self.id = id
        self.displayName = displayName
        self.manufacturer = manufacturer
        self.model = model
        self.bluetoothNames = Set(bluetoothNames.compactMap(Self.normalizeName))
        self.hidIdentity = hidIdentity
    }

    func matchesBluetoothName(_ rawName: String?) -> Bool {
        guard let normalized = Self.normalizeName(rawName) else { return false }
        return bluetoothNames.contains(normalized)
    }

    private static func normalizeName(_ rawName: String?) -> String? {
        guard let rawName else { return nil }
        let normalized = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum VoiceBridgeDeviceProfiles {
    static let xiaomiRC003 = VoiceBridgeDeviceProfile(
        id: "xiaomi-rc003",
        displayName: "Xiaomi Bluetooth Remote 2 Pro / RC003",
        manufacturer: "Xiaomi",
        model: "RC003",
        bluetoothNames: [
            "MI RC",
            "Xiaomi Bluetooth Remote 2 Pro",
            "小米蓝牙语音遥控器",
        ],
        hidIdentity: VoiceBridgeHIDIdentity(vendorID: 0x2717, productID: 0x32B8)
    )
}
