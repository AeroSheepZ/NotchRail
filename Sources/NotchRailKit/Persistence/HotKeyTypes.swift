import Foundation
import AppKit

/// Carbon 修饰键掩码具名常量（严格杜绝数值内联，AGENTS §0 规则 9）
public enum CarbonModifierMask {
    public static let cmdKey: UInt32 = 0x0100
    public static let shiftKey: UInt32 = 0x0200
    public static let optionKey: UInt32 = 0x0800
    public static let controlKey: UInt32 = 0x1000
}

/// macOS 经典物理键码具名常量（严格杜绝数值内联，AGENTS §0 规则 9）
public enum MacVirtualKeyCode {
    public static let kVK_ANSI_Grave: UInt32 = 0x32
    public static let kVK_ANSI_A: UInt32 = 0x00
    public static let kVK_ANSI_S: UInt32 = 0x01
    public static let kVK_ANSI_D: UInt32 = 0x02
    public static let kVK_ANSI_F: UInt32 = 0x03
    public static let kVK_ANSI_H: UInt32 = 0x04
    public static let kVK_ANSI_G: UInt32 = 0x05
    public static let kVK_ANSI_Z: UInt32 = 0x06
    public static let kVK_ANSI_X: UInt32 = 0x07
    public static let kVK_ANSI_C: UInt32 = 0x08
    public static let kVK_ANSI_V: UInt32 = 0x09
    public static let kVK_ANSI_B: UInt32 = 0x0B
    public static let kVK_ANSI_Q: UInt32 = 0x0C
    public static let kVK_ANSI_W: UInt32 = 0x0D
    public static let kVK_ANSI_E: UInt32 = 0x0E
    public static let kVK_ANSI_R: UInt32 = 0x0F
    public static let kVK_ANSI_Y: UInt32 = 0x10
    public static let kVK_ANSI_T: UInt32 = 0x11
    public static let kVK_ANSI_1: UInt32 = 0x12
    public static let kVK_ANSI_2: UInt32 = 0x13
    public static let kVK_ANSI_3: UInt32 = 0x14
    public static let kVK_ANSI_4: UInt32 = 0x15
    public static let kVK_ANSI_6: UInt32 = 0x16
    public static let kVK_ANSI_5: UInt32 = 0x17
    public static let kVK_ANSI_Equal: UInt32 = 0x18
    public static let kVK_ANSI_9: UInt32 = 0x19
    public static let kVK_ANSI_7: UInt32 = 0x1A
    public static let kVK_ANSI_Minus: UInt32 = 0x1B
    public static let kVK_ANSI_8: UInt32 = 0x1C
    public static let kVK_ANSI_0: UInt32 = 0x1D
    public static let kVK_ANSI_RightBracket: UInt32 = 0x1E
    public static let kVK_ANSI_O: UInt32 = 0x1F
    public static let kVK_ANSI_U: UInt32 = 0x20
    public static let kVK_ANSI_LeftBracket: UInt32 = 0x21
    public static let kVK_ANSI_I: UInt32 = 0x22
    public static let kVK_ANSI_P: UInt32 = 0x23
    public static let kVK_Return: UInt32 = 0x24
    public static let kVK_ANSI_L: UInt32 = 0x25
    public static let kVK_ANSI_J: UInt32 = 0x26
    public static let kVK_ANSI_Quote: UInt32 = 0x27
    public static let kVK_ANSI_K: UInt32 = 0x28
    public static let kVK_ANSI_Semicolon: UInt32 = 0x29
    public static let kVK_ANSI_Backslash: UInt32 = 0x2A
    public static let kVK_ANSI_Comma: UInt32 = 0x2B
    public static let kVK_ANSI_Slash: UInt32 = 0x2C
    public static let kVK_ANSI_N: UInt32 = 0x2D
    public static let kVK_ANSI_M: UInt32 = 0x2E
    public static let kVK_ANSI_Period: UInt32 = 0x2F
    public static let kVK_Tab: UInt32 = 0x30
    public static let kVK_Space: UInt32 = 0x31
    public static let kVK_Delete: UInt32 = 0x33
    public static let kVK_Escape: UInt32 = 0x35
    public static let kVK_LeftArrow: UInt32 = 0x7B
    public static let kVK_RightArrow: UInt32 = 0x7C
    public static let kVK_DownArrow: UInt32 = 0x7D
    public static let kVK_UpArrow: UInt32 = 0x7E
}

/// 快捷键展示与转换工具模型（从 UserPreferences 解耦，避免 Divergent Change 坏味道）
public struct HotKeyDisplayHelper: Sendable {
    /// 将 Carbon 修饰键转为键帽显示符号（如 "⌥"）
    public static func modifierGlyphs(for modifiers: UInt32) -> String {
        var glyphs = ""
        if (modifiers & CarbonModifierMask.controlKey) != 0 { glyphs += "⌃" }
        if (modifiers & CarbonModifierMask.optionKey) != 0 { glyphs += "⌥" }
        if (modifiers & CarbonModifierMask.shiftKey) != 0 { glyphs += "⇧" }
        if (modifiers & CarbonModifierMask.cmdKey) != 0 { glyphs += "⌘" }
        return glyphs
    }
    
    /// 将 NSEvent.ModifierFlags 转换为 Carbon 修饰键掩码
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= CarbonModifierMask.controlKey }
        if flags.contains(.option) { carbon |= CarbonModifierMask.optionKey }
        if flags.contains(.shift) { carbon |= CarbonModifierMask.shiftKey }
        if flags.contains(.command) { carbon |= CarbonModifierMask.cmdKey }
        return carbon
    }
    
    /// 将物理键码转换为直观按键字符
    public static func keyGlyph(for keyCode: UInt32) -> String {
        switch keyCode {
        case MacVirtualKeyCode.kVK_ANSI_Grave: return "~"
        case MacVirtualKeyCode.kVK_Space: return "Space"
        case MacVirtualKeyCode.kVK_Return: return "↩"
        case MacVirtualKeyCode.kVK_Tab: return "⇥"
        case MacVirtualKeyCode.kVK_Delete: return "⌫"
        case MacVirtualKeyCode.kVK_Escape: return "⎋"
        case MacVirtualKeyCode.kVK_UpArrow: return "↑"
        case MacVirtualKeyCode.kVK_DownArrow: return "↓"
        case MacVirtualKeyCode.kVK_LeftArrow: return "←"
        case MacVirtualKeyCode.kVK_RightArrow: return "→"
        // 数字键
        case MacVirtualKeyCode.kVK_ANSI_1: return "1"
        case MacVirtualKeyCode.kVK_ANSI_2: return "2"
        case MacVirtualKeyCode.kVK_ANSI_3: return "3"
        case MacVirtualKeyCode.kVK_ANSI_4: return "4"
        case MacVirtualKeyCode.kVK_ANSI_5: return "5"
        case MacVirtualKeyCode.kVK_ANSI_6: return "6"
        case MacVirtualKeyCode.kVK_ANSI_7: return "7"
        case MacVirtualKeyCode.kVK_ANSI_8: return "8"
        case MacVirtualKeyCode.kVK_ANSI_9: return "9"
        case MacVirtualKeyCode.kVK_ANSI_0: return "0"
        // 标点符号
        case MacVirtualKeyCode.kVK_ANSI_Minus: return "-"
        case MacVirtualKeyCode.kVK_ANSI_Equal: return "="
        case MacVirtualKeyCode.kVK_ANSI_LeftBracket: return "["
        case MacVirtualKeyCode.kVK_ANSI_RightBracket: return "]"
        case MacVirtualKeyCode.kVK_ANSI_Backslash: return "\\"
        case MacVirtualKeyCode.kVK_ANSI_Semicolon: return ";"
        case MacVirtualKeyCode.kVK_ANSI_Quote: return "'"
        case MacVirtualKeyCode.kVK_ANSI_Comma: return ","
        case MacVirtualKeyCode.kVK_ANSI_Period: return "."
        case MacVirtualKeyCode.kVK_ANSI_Slash: return "/"
        // 字母对照
        case MacVirtualKeyCode.kVK_ANSI_A: return "A"
        case MacVirtualKeyCode.kVK_ANSI_B: return "B"
        case MacVirtualKeyCode.kVK_ANSI_C: return "C"
        case MacVirtualKeyCode.kVK_ANSI_D: return "D"
        case MacVirtualKeyCode.kVK_ANSI_E: return "E"
        case MacVirtualKeyCode.kVK_ANSI_F: return "F"
        case MacVirtualKeyCode.kVK_ANSI_G: return "G"
        case MacVirtualKeyCode.kVK_ANSI_H: return "H"
        case MacVirtualKeyCode.kVK_ANSI_I: return "I"
        case MacVirtualKeyCode.kVK_ANSI_J: return "J"
        case MacVirtualKeyCode.kVK_ANSI_K: return "K"
        case MacVirtualKeyCode.kVK_ANSI_L: return "L"
        case MacVirtualKeyCode.kVK_ANSI_M: return "M"
        case MacVirtualKeyCode.kVK_ANSI_N: return "N"
        case MacVirtualKeyCode.kVK_ANSI_O: return "O"
        case MacVirtualKeyCode.kVK_ANSI_P: return "P"
        case MacVirtualKeyCode.kVK_ANSI_Q: return "Q"
        case MacVirtualKeyCode.kVK_ANSI_R: return "R"
        case MacVirtualKeyCode.kVK_ANSI_S: return "S"
        case MacVirtualKeyCode.kVK_ANSI_T: return "T"
        case MacVirtualKeyCode.kVK_ANSI_U: return "U"
        case MacVirtualKeyCode.kVK_ANSI_V: return "V"
        case MacVirtualKeyCode.kVK_ANSI_W: return "W"
        case MacVirtualKeyCode.kVK_ANSI_X: return "X"
        case MacVirtualKeyCode.kVK_ANSI_Y: return "Y"
        case MacVirtualKeyCode.kVK_ANSI_Z: return "Z"
        default:
            return "Key(\(keyCode))"
        }
    }
    
    /// 完整快捷键显示（如 "⌥ ~"）
    public static func displayString(modifiers: UInt32, keyCode: UInt32) -> String {
        let mod = modifierGlyphs(for: modifiers)
        let key = keyGlyph(for: keyCode)
        if mod.isEmpty {
            return key
        }
        return "\(mod) \(key)"
    }
}

/// NotchRail 权威版本元数据（AGENTS §0 事实唯一归属）
public enum NotchRailVersion {
    public static let CURRENT_VERSION = "1.0.0"
    public static let CURRENT_BUILD = "13"
}
