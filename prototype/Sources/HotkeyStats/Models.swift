import Foundation
import CoreGraphics

// MARK: - 数据模型

struct HotkeyRecord: Codable {
    var combo: String        // 归一化组合键，如 "⌘⌥T"
    var keycode: Int         // 物理 keycode
    var flagsRaw: UInt64     // 原始修饰键掩码（调试用）
    var count: Int           // 总次数
    var todayCount: Int      // 今日次数
    var todayDate: String    // "yyyy-MM-dd"，跨天惰性归零
    var firstSeen: Date
    var lastSeen: Date
}

// MARK: - 修饰键与组合键解析

enum ComboParser {

    struct Parsed {
        let combo: String    // 可读组合键名，如 "⌃⌥Space"；纯打字为 nil
        let isHotkey: Bool
    }

    private static let modifierMasks: [(String, UInt64)] = [
        ("⌃", CGEventFlags.maskControl.rawValue),
        ("⌥", CGEventFlags.maskAlternate.rawValue),
        ("⇧", CGEventFlags.maskShift.rawValue),
        ("⌘", CGEventFlags.maskCommand.rawValue),
    ]

    /// 解析一次按键。规则：
    /// 1. 修饰键组合 = 热键，归一化为 "⌃⌥⇧⌘+主键"；
    /// 2. Shift 为唯一修饰键且主键是字符键（字母/数字/标点）→ 视为打字，丢弃；
    /// 3. Shift 与功能键组合（⇧Tab/⇧F1）→ 热键；
    /// 4. 纯单键按下（无修饰键）→ 打字，丢弃。
    static func parse(keycode: Int, flagsRaw: UInt64) -> Parsed {
        let effective = flagsRaw & ~CGEventFlags.maskNonCoalesced.rawValue

        // CapsLock 状态位不影响判断（maskAlphaShift 只在读 CapsLock 灯时保留）
        let hasCmd  = effective & CGEventFlags.maskCommand.rawValue != 0
        let hasOpt  = effective & CGEventFlags.maskAlternate.rawValue != 0
        let hasCtrl = effective & CGEventFlags.maskControl.rawValue != 0
        let hasShift = effective & CGEventFlags.maskShift.rawValue != 0
        let hasFn   = effective & CGEventFlags.maskSecondaryFn.rawValue != 0
        let hasAnyModifier = hasCmd || hasOpt || hasCtrl || hasShift || hasFn

        guard hasAnyModifier else { return Parsed(combo: "", isHotkey: false) }

        // Shift 为唯一修饰键 + 字符类主键 → 大写字母/数字符号输入，属于打字
        let isCharacterKey = KeyMapper.isCharacterKey(keycode)
        if hasShift && !hasCmd && !hasOpt && !hasCtrl && !hasFn && isCharacterKey {
            return Parsed(combo: "", isHotkey: false)
        }

        var prefix = ""
        for (symbol, mask) in modifierMasks where effective & mask != 0 {
            prefix += symbol
        }
        if hasFn { prefix = "fn" + prefix }

        return Parsed(combo: prefix + KeyMapper.name(for: keycode), isHotkey: true)
    }


}

// MARK: - keycode → 可读名

enum KeyMapper {

    // macOS ANSI 物理键位，不随输入法或键盘布局变化。
    private static let letters: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
    ]

    static func isCharacterKey(_ keycode: Int) -> Bool {
        letters[keycode] != nil || digits[keycode] != nil || punctuation[keycode] != nil
    }

    private static let special: [Int: String] = [
        36: "Return", 48: "Tab", 49: "Space", 53: "Esc", 51: "Delete", 117: "ForwardDelete",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        105: "F13", 107: "F14", 113: "F15",
    ]

    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let digits: [Int: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
        23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    private static let punctuation: [Int: String] = [
        33: "[", 30: "]", 42: "\\", 39: "'", 41: ";", 27: "-",
        24: "=", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    static func name(for keycode: Int) -> String {
        return letters[keycode]
            ?? special[keycode]
            ?? functionKeys[keycode]
            ?? digits[keycode]
            ?? punctuation[keycode]
            ?? "Key(\(keycode))"
    }
}

// MARK: - 日期工具

enum DayKey {
    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
