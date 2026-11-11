import AppKit
import ServiceManagement
import Carbon

enum ShortcutKeys {
    static let values: [(String, UInt32)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),
        ("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),("Q",12),("R",15),
        ("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),
        ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25)]
    static func valid(key: UInt32, modifiers: UInt32) -> Bool {
        values.contains { $0.1 == key } && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 && modifiers & ~UInt32(controlKey | optionKey | cmdKey | shiftKey) == 0
    }
    static func label(_ value: Preferences) -> String {
        var result = ""
        for (mask, text) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] where value.modifiers & UInt32(mask) != 0 { result += text }
        return result + (values.first { $0.1 == value.keyCode }?.0 ?? "Z")
    }
}

final class SettingsController: NSObject, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let language = NSPopUpButton()
    private let moveUsed = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let limit = NSTextField()
    private let key = NSPopUpButton()
    private var modifiers: [(UInt32, NSButton)] = []
    private var labels: [String: NSTextField] = [:]
    private let save = NSButton()
    private let cancel = NSButton()
    private let about = NSTextField(labelWithString: "Chojema CopyKeep 0.2.0 · Park Chulwoo")
    var onSave: ((Preferences, Bool) -> Bool)?
    var onLanguage: ((String) -> Void)?
    private var original = Preferences()

    override init() {
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = Palette.background
        let root = ThemedView(fill: { Palette.background })
        window.contentView = root
        func label(_ name: String, _ y: CGFloat) {
            let field = NSTextField(labelWithString: tr(name))
            field.frame = NSRect(x: 24, y: y, width: 170, height: 23)
            labels[name] = field
            root.addSubview(field)
        }
        label("language", 384)
        language.frame = NSRect(x: 200, y: 380, width: 310, height: 28)
        language.addItems(withTitles: ["한국어", "English"])
        language.target = self; language.action = #selector(changeLanguage)
        label("shortcut", 330)
        key.frame = NSRect(x: 425, y: 326, width: 85, height: 28)
        key.addItems(withTitles: ShortcutKeys.values.map(\.0))
        for (index, pair) in [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")].enumerated() {
            let button = NSButton(checkboxWithTitle: pair.1, target: nil, action: nil)
            button.frame = NSRect(x: 200 + index * 55, y: 330, width: 55, height: 22)
            button.setAccessibilityLabel(tr(["controlKey", "optionKey", "shiftKey", "commandKey"][index]))
            modifiers.append((pair.0, button)); root.addSubview(button)
        }
        moveUsed.frame = NSRect(x: 24, y: 263, width: 490, height: 24)
        login.frame = NSRect(x: 24, y: 220, width: 490, height: 24)
        label("limit", 169)
        limit.frame = NSRect(x: 200, y: 166, width: 100, height: 26)
        label("limits", 119)
        labels["limits"]?.frame.size.width = 490
        labels["limits"]?.font = .systemFont(ofSize: 11)
        labels["limits"]?.textColor = .secondaryLabelColor
        about.frame = NSRect(x: 24, y: 77, width: 490, height: 20)
        about.font = .systemFont(ofSize: 12)
        about.textColor = .secondaryLabelColor
        save.frame = NSRect(x: 400, y: 21, width: 110, height: 32)
        save.target = self; save.action = #selector(saveChanges); save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        cancel.frame = NSRect(x: 280, y: 21, width: 110, height: 32)
        cancel.target = self; cancel.action = #selector(close); cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        [language, key, moveUsed, login, limit, about, save, cancel].forEach(root.addSubview)
        refreshLanguage()
    }

    func refreshLanguage() {
        window.title = tr("settings")
        labels.forEach { $0.value.stringValue = tr($0.key) }
        language.setAccessibilityLabel(tr("language"))
        key.setAccessibilityLabel(tr("shortcutKey"))
        limit.setAccessibilityLabel(tr("limit"))
        for (index, pair) in modifiers.enumerated() {
            pair.1.setAccessibilityLabel(tr(["controlKey", "optionKey", "shiftKey", "commandKey"][index]))
        }
        moveUsed.title = tr("moveUsed")
        login.title = tr("login")
        save.title = tr("save")
        cancel.title = tr("cancel")
    }

    func show(_ value: Preferences) {
        original = value
        language.selectItem(at: value.language == "en-US" ? 1 : 0)
        moveUsed.state = value.moveUsed ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval ? .on : .off
        limit.stringValue = String(value.limit)
        key.selectItem(at: ShortcutKeys.values.firstIndex { $0.1 == value.keyCode } ?? 25)
        modifiers.forEach { $0.1.state = value.modifiers & $0.0 != 0 ? .on : .off }
        refreshLanguage()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func changeLanguage() {
        original.language = Localization.languages[language.indexOfSelectedItem]
        onLanguage?(original.language)
        refreshLanguage()
    }

    @objc private func saveChanges() {
        guard let count = Int(limit.stringValue), (10...1000).contains(count) else { showAlert("invalidLimit"); return }
        var next = original
        next.limit = count
        next.moveUsed = moveUsed.state == .on
        next.keyCode = ShortcutKeys.values[key.indexOfSelectedItem].1
        next.modifiers = modifiers.reduce(0) { $0 | ($1.1.state == .on ? $1.0 : 0) }
        guard ShortcutKeys.valid(key: next.keyCode, modifiers: next.modifiers) else { showAlert("invalidShortcut"); return }
        if onSave?(next, login.state == .on) == true { close() }
    }

    @objc private func close() { window.orderOut(nil) }
}

func showAlert(_ key: String) {
    let alert = NSAlert()
    alert.messageText = "Chojema CopyKeep"
    alert.informativeText = tr(key)
    alert.addButton(withTitle: tr("ok"))
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}
