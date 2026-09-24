import Carbon.HIToolbox

/// macOS virtual key codes (Carbon kVK_*) and their display names.
public enum KeyCodes {
    public static let table: [(code: Int, name: String)] = [
        (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
        (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
        (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
        (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
        (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
        (kVK_ANSI_Z, "Z"),
        (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
        (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        (kVK_ANSI_LeftBracket, "["), (kVK_ANSI_RightBracket, "]"), (kVK_ANSI_Minus, "-"), (kVK_ANSI_Equal, "="),
        (kVK_ANSI_Semicolon, ";"), (kVK_ANSI_Quote, "'"), (kVK_ANSI_Comma, ","), (kVK_ANSI_Period, "."),
        (kVK_ANSI_Slash, "/"), (kVK_ANSI_Backslash, "\\"), (kVK_ANSI_Grave, "`"),
        (kVK_Return, "Return"), (kVK_Tab, "Tab"), (kVK_Space, "Space"), (kVK_Delete, "Delete"),
        (kVK_ForwardDelete, "ForwardDelete"), (kVK_Escape, "Escape"),
        (kVK_LeftArrow, "Left"), (kVK_RightArrow, "Right"), (kVK_UpArrow, "Up"), (kVK_DownArrow, "Down"),
        (kVK_Home, "Home"), (kVK_End, "End"), (kVK_PageUp, "PageUp"), (kVK_PageDown, "PageDown"),
        (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"), (kVK_F5, "F5"), (kVK_F6, "F6"),
        (kVK_F7, "F7"), (kVK_F8, "F8"), (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
    ]

    private static let symbols: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
    ]

    public static func name(for code: UInt16) -> String {
        let c = Int(code)
        return symbols[c] ?? table.first { $0.code == c }?.name ?? "Key \(c)"
    }

    public static func code(named name: String) -> UInt16? {
        table.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { UInt16($0.code) }
    }

    /// Parses "cmd+shift+[" / "ctrl+left" style strings.
    public static func parseCombo(_ string: String) -> KeyCombo? {
        var parts = string.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        // "cmd++" → last part is "+"; not supported, keep it simple.
        guard let keyName = parts.popLast(), let code = code(named: keyName) else { return nil }
        var combo = KeyCombo(keyCode: code)
        for mod in parts.map({ $0.lowercased() }) {
            switch mod {
            case "cmd", "command", "⌘": combo.command = true
            case "opt", "option", "alt", "⌥": combo.option = true
            case "ctrl", "control", "⌃": combo.control = true
            case "shift", "⇧": combo.shift = true
            default: return nil
            }
        }
        return combo
    }
}
