import AppKit
import Carbon
import SwiftUI

enum HotkeyError: LocalizedError, Equatable {
    case modifierRequired
    case reserved
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .modifierRequired: "Use Command, Option, Control, or Shift with the key."
        case .reserved: "That shortcut is reserved by macOS."
        case .unavailable: "That shortcut is unavailable. Choose another one."
        }
    }
}

struct Hotkey: Equatable {
    static let defaultValue = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey))

    let keyCode: UInt32
    let modifiers: UInt32

    var title: String { modifierTitle + keyTitle }

    func validate() throws {
        guard modifiers != 0 else { throw HotkeyError.modifierRequired }
        guard !Self.isReserved(keyCode: keyCode, modifiers: modifiers) else { throw HotkeyError.reserved }
    }

    static func from(_ event: NSEvent) -> Hotkey {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private var modifierTitle: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    private var keyTitle: String {
        switch keyCode {
        case UInt32(kVK_Space): "Space"
        case UInt32(kVK_Return): "↩"
        case UInt32(kVK_Tab): "⇥"
        case UInt32(kVK_Escape): "⎋"
        case UInt32(kVK_Delete): "⌫"
        case UInt32(kVK_ANSI_A): "A"
        case UInt32(kVK_ANSI_B): "B"
        case UInt32(kVK_ANSI_C): "C"
        case UInt32(kVK_ANSI_D): "D"
        case UInt32(kVK_ANSI_E): "E"
        case UInt32(kVK_ANSI_F): "F"
        case UInt32(kVK_ANSI_G): "G"
        case UInt32(kVK_ANSI_H): "H"
        case UInt32(kVK_ANSI_I): "I"
        case UInt32(kVK_ANSI_J): "J"
        case UInt32(kVK_ANSI_K): "K"
        case UInt32(kVK_ANSI_L): "L"
        case UInt32(kVK_ANSI_M): "M"
        case UInt32(kVK_ANSI_N): "N"
        case UInt32(kVK_ANSI_O): "O"
        case UInt32(kVK_ANSI_P): "P"
        case UInt32(kVK_ANSI_Q): "Q"
        case UInt32(kVK_ANSI_R): "R"
        case UInt32(kVK_ANSI_S): "S"
        case UInt32(kVK_ANSI_T): "T"
        case UInt32(kVK_ANSI_U): "U"
        case UInt32(kVK_ANSI_V): "V"
        case UInt32(kVK_ANSI_W): "W"
        case UInt32(kVK_ANSI_X): "X"
        case UInt32(kVK_ANSI_Y): "Y"
        case UInt32(kVK_ANSI_Z): "Z"
        case UInt32(kVK_ANSI_0): "0"
        case UInt32(kVK_ANSI_1): "1"
        case UInt32(kVK_ANSI_2): "2"
        case UInt32(kVK_ANSI_3): "3"
        case UInt32(kVK_ANSI_4): "4"
        case UInt32(kVK_ANSI_5): "5"
        case UInt32(kVK_ANSI_6): "6"
        case UInt32(kVK_ANSI_7): "7"
        case UInt32(kVK_ANSI_8): "8"
        case UInt32(kVK_ANSI_9): "9"
        default: "Key \(keyCode)"
        }
    }

    private static func isReserved(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if modifiers == UInt32(cmdKey), [UInt32(kVK_Space), UInt32(kVK_Tab), UInt32(kVK_ANSI_Q)].contains(keyCode) {
            return true
        }
        return modifiers == UInt32(cmdKey | shiftKey)
            && (UInt32(kVK_ANSI_3)...UInt32(kVK_ANSI_6)).contains(keyCode)
    }
}

final class GlobalHotkey {
    private static let signature: OSType = 0x556A6572 // "Ujer"
    private var handler: EventHandlerRef?
    private var registered: EventHotKeyRef?
    private var current: Hotkey?

    deinit {
        if let registered { UnregisterEventHotKey(registered) }
        if let handler { RemoveEventHandler(handler) }
    }

    func replace(with shortcut: Hotkey) throws {
        try shortcut.validate()
        if current == shortcut { return }
        try installHandlerIfNeeded()

        var candidate: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { throw HotkeyError.unavailable(status) }

        if let registered { UnregisterEventHotKey(registered) }
        registered = candidate
        current = shortcut
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), Self.handle, 1, &eventType, nil, &handler)
        guard status == noErr else { throw HotkeyError.unavailable(status) }
    }

    private static let handle: EventHandlerUPP = { _, event, _ in
        guard let event else { return noErr }
        var id = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, id.signature == signature else { return noErr }
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.hotkeyPressed()
        }
        return noErr
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    let shortcut: Hotkey
    let onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.shortcut = shortcut
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.onCapture = onCapture
    }
}

final class RecorderView: NSView {
    var shortcut = Hotkey.defaultValue { didSet { needsDisplay = true } }
    var onCapture: ((Hotkey) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        let text = shortcut.title as NSString
        text.draw(at: NSPoint(x: 8, y: (bounds.height - text.size(withAttributes: attributes).height) / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }
        onCapture?(Hotkey.from(event))
        window?.makeFirstResponder(nil)
    }
}
