import AppKit
import ApplicationServices

@MainActor
struct FocusTarget {
    let pid: pid_t
    let application: AXUIElement
    let element: AXUIElement?
}

enum InjectionResult {
    case inserted
    case copiedOnly(String)
}

@MainActor
enum FocusInjector {
    static func requestAccessibilityTrust() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func capture() throws -> FocusTarget {
        guard AXIsProcessTrusted() else { throw AccessibilityError.notTrusted }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityError.noFocusedApplication
        }
        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApplication, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let rawElement = value,
           CFGetTypeID(rawElement) == AXUIElementGetTypeID() {
            let element = unsafeDowncast(rawElement, to: AXUIElement.self)
            return FocusTarget(pid: application.processIdentifier, application: axApplication, element: element)
        }
        // Clicking a status item can temporarily remove the AX focused element.
        // Keep the frontmost app and use verified clipboard insertion on completion.
        return FocusTarget(pid: application.processIdentifier, application: axApplication, element: nil)
    }

    static func insert(_ transcript: String, into target: FocusTarget) -> InjectionResult {
        copy(transcript)
        guard verifyApplication(target) else {
            return .copiedOnly("Target focus changed; transcript was copied instead.")
        }
        guard let element = target.element else {
            return pasteIntoApplication(target: target)
        }
        guard !isSecureTextField(element) else {
            return .copiedOnly("Secure fields are never filled; transcript was copied instead.")
        }

        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        _ = AXUIElementSetAttributeValue(target.application, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard verify(target) else {
            return .copiedOnly("Target focus changed; transcript was copied instead.")
        }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, transcript as CFString) == .success {
            return .inserted
        }

        return pasteIntoApplication(target: target)
    }

    private static func pasteIntoApplication(target: FocusTarget) -> InjectionResult {
        NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        guard verifyApplication(target) else {
            return .copiedOnly("Target focus changed; transcript was copied instead.")
        }
        guard postPaste() else {
            return .copiedOnly("Ujer could not send the paste command; transcript was copied instead.")
        }
        return .inserted
    }

    static func copy(_ transcript: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private static func verify(_ target: FocusTarget) -> Bool {
        guard verifyApplication(target), let element = target.element
        else {
            return false
        }
        var current: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.application, kAXFocusedUIElementAttribute as CFString, &current) == .success,
              let rawFocused = current,
              CFGetTypeID(rawFocused) == AXUIElementGetTypeID()
        else {
            return false
        }
        let focused = unsafeDowncast(rawFocused, to: AXUIElement.self)
        return CFEqual(focused, element)
    }

    private static func verifyApplication(_ target: FocusTarget) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
            && NSRunningApplication(processIdentifier: target.pid) != nil
    }

    private static func isSecureTextField(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String
        else {
            return false
        }
        return role == "AXSecureTextField"
    }

    private static func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

enum AccessibilityError: LocalizedError {
    case notTrusted
    case noFocusedApplication
    case noFocusedElement

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "Allow Ujer in System Settings > Privacy & Security > Accessibility."
        case .noFocusedApplication:
            "No target application is active."
        case .noFocusedElement:
            "No text field is focused."
        }
    }
}
