import AppKit
import ApplicationServices
import Carbon

struct ReplacementMatcher {
    var rules: [String: String] = [:]
    private(set) var buffer = ""

    static func valid(_ abbreviation: String) -> Bool {
        abbreviation.isEmpty || ((2...64).contains(abbreviation.utf8.count) && abbreviation.utf8.allSatisfy { (33...126).contains($0) })
    }

    mutating func reset() { buffer = "" }

    mutating func append(_ text: String) -> (String, String)? {
        guard text.utf8.count == 1, let byte = text.utf8.first, (33...126).contains(byte) else { reset(); return nil }
        buffer = String((buffer + text).suffix(65))
        for (abbreviation, body) in rules where !abbreviation.isEmpty && buffer.hasSuffix(abbreviation) {
            let prefix = buffer.dropLast(abbreviation.count)
            if let first = abbreviation.utf8.first, Self.word(first), let previous = prefix.utf8.last, Self.word(previous) { continue }
            return (abbreviation, body)
        }
        return nil
    }

    private static func word(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95
    }
}

final class TextReplacement {
    var matcher = ReplacementMatcher()
    var onReplace: ((String, String, pid_t) -> Void)?
    private var monitor: Any?
    private var localMonitor: Any?
    private var process: pid_t = 0
    private var pending: (String, String)?
    private var pendingKey: UInt16 = 0

    func start() -> Bool {
        stop()
        guard !matcher.rules.isEmpty else { return true }
        guard AXIsProcessTrusted() else { return false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] in self?.receive($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            self?.reset(); return event
        }
        return monitor != nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil; localMonitor = nil; reset()
    }

    private func reset() { matcher.reset(); pending = nil }

    private func receive(_ event: NSEvent) {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() }
        guard type != kTISTypeKeyboardInputMode, !IsSecureEventInputEnabled(), let front = NSWorkspace.shared.frontmostApplication else { reset(); return }
        if event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return }
        if front.processIdentifier != process { reset(); process = front.processIdentifier }
        guard event.type == .keyDown || event.type == .keyUp else { reset(); return }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { reset(); return }
        if event.type == .keyDown {
            guard !event.isARepeat else { reset(); return }
            pending = matcher.append(event.characters ?? ""); pendingKey = event.keyCode
        } else if event.keyCode == pendingKey, let (abbreviation, body) = pending {
            reset(); onReplace?(abbreviation, body, process)
        }
    }

    // Select only a verified abbreviation immediately before an empty insertion point.
    static func selectAbbreviation(_ abbreviation: String, process: pid_t) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == process else { return false }
        let app = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focus) == .success,
              let focus, CFGetTypeID(focus) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(focus, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole else { return false }
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
              let selection, CFGetTypeID(selection) == AXValueGetTypeID() else { return false }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(selection, to: AXValue.self), .cfRange, &range), range.length == 0 else { return false }
        let length = abbreviation.utf16.count
        guard range.location >= length else { return false }
        range = CFRange(location: range.location - length, length: length)
        var content: CFTypeRef?
        guard let selected = AXValueCreate(.cfRange, &range),
              AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, selected, &content) == .success,
              content as? String == abbreviation,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == process else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selected) == .success
    }

    deinit { stop() }
}
