import AppKit

enum Palette {
    static var background: NSColor { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .windowBackgroundColor : adaptive(light: (0.957, 0.969, 0.969), dark: (0.114, 0.129, 0.129)) }
    static var accent: NSColor { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .controlAccentColor : adaptive(light: (0.09, 0.42, 0.39), dark: (0.36, 0.76, 0.71)) }

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        }
    }
}

/// Layer-backed surface whose colors follow the effective appearance (light or dark).
final class ThemedView: NSView {
    private let fill: () -> NSColor
    private let border: NSColor?
    private let radius: CGFloat

    init(fill: @escaping () -> NSColor, border: NSColor? = nil, radius: CGFloat = 0) {
        self.fill = fill
        self.border = border
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill().cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.borderColor = border?.cgColor
    }
}

final class HistoryRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 6, yRadius: 6)
        Palette.accent.withAlphaComponent(0.10).setFill()
        path.fill()
        Palette.accent.setStroke()
        path.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
        path.stroke()
    }
}

final class HistoryPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

final class HistoryTable: NSTableView {
    var onHover: ((Int) -> Void)?
    private var tracking: NSTrackingArea?
    private var lastPoint: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard point != lastPoint else { return }
        lastPoint = point
        onHover?(row(at: convert(event.locationInWindow, from: nil)))
    }
    override func mouseExited(with event: NSEvent) { lastPoint = nil; onHover?(-1) }
}

final class PopupController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 410),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
    let table = HistoryTable()
    private let scroll = NSScrollView()
    private let title = NSTextField(labelWithString: "Chojema CopyKeep")
    private let count = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let previewBox = ThemedView(fill: { .controlBackgroundColor }, border: .separatorColor, radius: 10)
    private let previewTitle = NSTextField(labelWithString: "")
    private let previewScroll = NSScrollView()
    private let previewText = NSTextView()
    private let previewImage = NSImageView()
    private var buttons: [String: NSButton] = [:]
    private var hoverTimer: Timer?
    private(set) var hoverRow = -1
    private(set) var showsPreview = false
    private(set) var items: [HistoryItem] = []
    private var anchor = NSPoint.zero
    private var screen = NSRect.zero
    var onPaste: ((HistoryItem) -> Void)?
    var onDelete: ((HistoryItem) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: (() -> Void)?

    override init() {
        super.init()
        panel.title = "Chojema CopyKeep"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.backgroundColor = Palette.background
        panel.hasShadow = true
        let root = ThemedView(fill: { Palette.background })
        panel.contentView = root
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        count.font = .systemFont(ofSize: 12)
        count.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        [title, count, hint, empty, scroll, previewBox].forEach(root.addSubview)
        title.frame = NSRect(x: 16, y: 366, width: 300, height: 25)
        count.frame = NSRect(x: 16, y: 343, width: 380, height: 18)
        scroll.frame = NSRect(x: 10, y: 80, width: 400, height: 254)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.width = 378
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 36
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.onHover = { [weak self] row in self?.scheduleHover(row) }
        table.setAccessibilityLabel(tr("history"))
        empty.frame = NSRect(x: 30, y: 170, width: 360, height: 80)
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 53, width: 385, height: 18)
        addButton("settings", action: #selector(settings), frame: NSRect(x: 12, y: 13, width: 95, height: 30))
        addButton("delete", action: #selector(deleteSelected), frame: NSRect(x: 115, y: 13, width: 105, height: 30))
        addButton("clear", action: #selector(clear), frame: NSRect(x: 228, y: 13, width: 110, height: 30))
        addButton("close", action: #selector(close), frame: NSRect(x: 371, y: 365, width: 34, height: 28))
        previewBox.frame = NSRect(x: 430, y: 14, width: 356, height: 382)
        [previewTitle, previewScroll, previewImage].forEach(previewBox.addSubview)
        previewTitle.frame = NSRect(x: 14, y: 346, width: 328, height: 22)
        previewTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        previewScroll.frame = NSRect(x: 12, y: 12, width: 332, height: 324)
        previewScroll.hasVerticalScroller = true
        previewScroll.documentView = previewText
        previewText.isEditable = false
        previewText.isSelectable = true
        previewText.isRichText = false
        previewText.font = .systemFont(ofSize: 14)
        previewText.textContainerInset = NSSize(width: 8, height: 8)
        previewText.isHorizontallyResizable = false
        previewText.isVerticallyResizable = true
        previewText.autoresizingMask = [.width]
        previewText.textContainer?.widthTracksTextView = true
        previewImage.frame = previewScroll.frame
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        refreshLanguage()
    }

    private func addButton(_ key: String, action: Selector, frame: NSRect) {
        let button = NSButton(title: tr(key), target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = frame
        button.contentTintColor = Palette.accent
        panel.contentView!.addSubview(button)
        buttons[key] = button
    }

    func refreshLanguage() {
        buttons.forEach { key, button in
            button.title = key == "close" ? "×" : tr(key)
            button.setAccessibilityLabel(tr(key))
        }
        table.setAccessibilityLabel(tr("history"))
        empty.stringValue = tr("empty")
        hint.stringValue = tr("keys")
        previewTitle.stringValue = tr("preview")
        previewText.setAccessibilityLabel(tr("preview"))
        previewImage.setAccessibilityLabel(tr("image"))
        updateCount()
        table.reloadData()
    }

    private func updateCount() { count.stringValue = String(format: tr("count"), items.count) }

    func show(items: [HistoryItem], anchor: NSPoint, screen: NSRect) {
        self.anchor = anchor
        self.screen = screen
        reload(items)
        if !items.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(table)
    }

    func reload(_ items: [HistoryItem]) {
        let row = max(0, min(table.selectedRow, items.count - 1))
        self.items = items
        cancelHover()
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        empty.isHidden = !items.isEmpty
        buttons["delete"]?.isEnabled = !items.isEmpty
        buttons["clear"]?.isEnabled = !items.isEmpty
        updateCount()
        updatePreview()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { HistoryRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 378, height: 36))
        let symbol = item.kind == "image" ? "photo" : "doc.text"
        let icon = NSImageView(frame: NSRect(x: 9, y: 9, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tr(item.kind))
        icon.contentTintColor = Palette.accent
        let label = NSTextField(labelWithString: item.kind == "text" ? item.text.components(separatedBy: .newlines).joined(separator: " ").replacingOccurrences(of: "\t", with: " ") : tr("image"))
        label.frame = NSRect(x: 36, y: 8, width: 332, height: 20)
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.textField = label
        cell.imageView = icon
        cell.setAccessibilityLabel(tr(item.kind) + ": " + label.stringValue)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { cancelHover(); updatePreview() }

    func scheduleHover(_ row: Int) {
        hoverTimer?.invalidate()
        guard items.indices.contains(row) else { cancelHover(); updatePreview(); return }
        if hoverRow == row { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.hoverRow = row
            self?.updatePreview()
        }
    }

    private func cancelHover() { hoverTimer?.invalidate(); hoverTimer = nil; hoverRow = -1 }

    private func updatePreview() {
        let row = hoverRow >= 0 ? hoverRow : table.selectedRow
        let item = items.indices.contains(row) ? items[row] : nil
        showsPreview = item.map { ClipboardContent.needsPreview($0) } ?? false
        previewBox.isHidden = !showsPreview
        if let item, showsPreview {
            previewImage.isHidden = item.kind != "image"
            previewScroll.isHidden = item.kind == "image"
            previewImage.image = item.kind == "image" ? NSImage(data: item.payload) : nil
            previewText.string = item.kind == "text" ? item.text : ""
            previewText.frame = NSRect(x: 0, y: 0, width: 332, height: 324)
            previewText.scrollToBeginningOfDocument(nil)
        }
        panel.setFrame(PopupPlacement.frame(anchor: anchor, size: NSSize(width: showsPreview ? 800 : 420, height: 410), screen: screen), display: true)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: close(); return true
        case 36, 76: pasteSelected(); return true
        case 51, 117: deleteSelected(); return true
        case 125, 126:
            guard !items.isEmpty else { return true }
            let row = min(items.count - 1, max(0, table.selectedRow + (event.keyCode == 125 ? 1 : -1)))
            cancelHover()
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            updatePreview()
            return true
        default: return false
        }
    }

    @objc func clicked() { if table.clickedRow >= 0 { pasteSelected() } }
    func pasteSelected() { if items.indices.contains(table.selectedRow) { onPaste?(items[table.selectedRow]) } }
    @objc func deleteSelected() { if items.indices.contains(table.selectedRow) { onDelete?(items[table.selectedRow]) } }
    @objc private func settings() { close(); onSettings?() }
    @objc private func clear() { onClear?() }
    @objc func close() { cancelHover(); panel.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { close() }

    func snapshot(to url: URL) throws {
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw StoreError.invalidItem }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StoreError.invalidItem }
        try png.write(to: url)
    }
}
