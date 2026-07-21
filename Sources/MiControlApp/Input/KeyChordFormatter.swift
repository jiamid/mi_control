import AppKit
import CoreGraphics
import Foundation

enum KeyChordFormatter {
    static func displayName(keyCode: UInt16, modifiers: UInt64) -> String {
        let flags = CGEventFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "空格", 50: "`",
            51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
            100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "↖",
            116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟",
            122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }

    /// 录制时只保留真正的修饰位，去掉与设备相关的噪声。
    static func normalizedModifiers(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result = CGEventFlags()
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result.rawValue
    }
}
