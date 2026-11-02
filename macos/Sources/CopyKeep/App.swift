import AppKit
import ApplicationServices
import ServiceManagement

final class AppController: NSObject, NSApplicationDelegate {
    var store: HistoryStore!
    var preferences = Preferences()
    let popup = PopupController()
    let settings = SettingsController()
    private let hotKey = HotKey()
    private var status: NSStatusItem?
    private var timer: Timer?
    private var lastChange = 0
    private var paused = false
    private var target: NSRunningApplication?
    private var pastePending = false
    private var collectionErrorShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-test") { runSmoke(); return }
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.chojema.CopyKeep")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other { other.activate(options: []); NSApp.terminate(nil); return }
        do {
            let directory: URL
            if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), CommandLine.arguments.indices.contains(index + 1) {
                directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("ChojemaCopyKeep", isDirectory: true)
            }
            store = try HistoryStore(directory: directory)
            preferences = try store.loadPreferences()
            if !ShortcutKeys.valid(key: preferences.keyCode, modifiers: preferences.modifiers) {
                preferences.keyCode = Preferences().keyCode
                preferences.modifiers = Preferences().modifiers
            }
            Localization.shared.language = preferences.language
        } catch { showAlert("storageError"); NSApp.terminate(nil); return }
        wireActions()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Chojema CopyKeep")
        refreshLanguage()
        hotKey.onPress = { [weak self] in self?.openHistory() }
        if !hotKey.register(key: preferences.keyCode, modifiers: preferences.modifiers) { showAlert("shortcutConflict") }
        lastChange = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.collect() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openHistory(); return false }

    private func wireActions() {
        popup.onPaste = { [weak self] in self?.paste($0) }
        popup.onDelete = { [weak self] item in self?.modifyHistory { try self?.store.delete(item.id) } }
        popup.onClear = { [weak self] in self?.clearHistory() }
        popup.onSettings = { [weak self] in self?.openSettings() }
        settings.onLanguage = { [weak self] language in
            guard let self else { return }
            var next = self.preferences
            next.language = language
            do { try self.store.savePreferences(next); self.preferences = next; self.refreshLanguage() }
            catch { showAlert("storageError") }
        }
        settings.onSave = { [weak self] value, login in self?.saveSettings(value, login: login) ?? false }
    }

    private func refreshLanguage() {
        Localization.shared.language = preferences.language
        popup.refreshLanguage()
        settings.refreshLanguage()
        let menu = NSMenu()
        for (key, action) in [("history", #selector(openHistory)), ("settings", #selector(openSettings)),
                              (paused ? "resume" : "pause", #selector(togglePause)), ("quit", #selector(quit))] {
            if key == "quit" { menu.addItem(.separator()) }
            let title = key == "history" ? tr(key) + "  " + ShortcutKeys.label(preferences) : tr(key)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        status?.menu = menu
        status?.button?.toolTip = "Chojema CopyKeep · " + tr(paused ? "paused" : "running")
        status?.button?.setAccessibilityLabel("Chojema CopyKeep · " + tr(paused ? "paused" : "running"))
    }

    private func collect() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard !paused, let (kind, data) = ClipboardContent.read(pasteboard) else { return }
        do {
            try store.add(kind: kind, payload: data, limit: preferences.limit)
            collectionErrorShown = false
            if popup.panel.isVisible { popup.reload(try store.list()) }
        } catch {
            // Stop collection after a storage failure; retry only when the user resumes it.
            paused = true; refreshLanguage()
            if !collectionErrorShown { collectionErrorShown = true; showAlert("collectionError") }
        }
    }

    @objc func openHistory() {
        guard store != nil, !pastePending else { return }
        if popup.panel.isVisible { popup.close(); return }
        target = NSWorkspace.shared.frontmostApplication
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier { target = nil }
        let anchor = caretPosition() ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        do { popup.show(items: try store.list(), anchor: anchor, screen: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)) }
        catch { showAlert("storageError") }
    }

    private func caretPosition() -> NSPoint? {
        guard AXIsProcessTrusted(), let target else { return nil }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        var focus: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focus) == .success,
              let focus, CFGetTypeID(focus) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focus, to: AXUIElement.self)
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let bounds = unsafeBitCast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetValue(bounds, .cgRect, &rect), let primary = NSScreen.screens.first,
              rect.origin.x.isFinite, rect.origin.y.isFinite else { return nil }
        return NSPoint(x: rect.maxX, y: primary.frame.maxY - rect.maxY)
    }

    private func paste(_ item: HistoryItem) {
        guard !pastePending else { return }
        guard let target, !target.isTerminated else { showAlert("noTarget"); return }
        guard AXIsProcessTrusted() else {
            popup.close()
            let alert = NSAlert()
            alert.messageText = tr("accessibilityTitle")
            alert.informativeText = tr("accessibilityBody")
            alert.addButton(withTitle: tr("openSettings"))
            alert.addButton(withTitle: tr("cancel"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { showAlert("pasteError"); return }
        down.flags = .maskCommand; up.flags = .maskCommand
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let written = item.kind == "image" ? pasteboard.setData(item.payload, forType: .png) : pasteboard.setString(item.text, forType: .string)
        lastChange = pasteboard.changeCount
        guard written else { showAlert("pasteError"); return }
        popup.close()
        guard target.activate(options: []) else { showAlert("pasteError"); return }
        pastePending = true
        // Wait for the destination to regain focus before sending the shortcut.
        let deadline = Date().addingTimeInterval(1)
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                timer.invalidate(); self.pastePending = false
                guard AXIsProcessTrusted(), !target.isTerminated else { showAlert("pasteError"); return }
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                if self.preferences.moveUsed {
                    do { try self.store.touch(item.id) } catch { showAlert("storageError") }
                }
            } else if Date() >= deadline {
                timer.invalidate(); self.pastePending = false; showAlert("pasteError")
            }
        }
    }

    private func modifyHistory(_ action: () throws -> Void) {
        do { try action(); popup.reload(try store.list()) } catch { showAlert("storageError") }
    }

    private func clearHistory() {
        popup.close()
        let alert = NSAlert()
        alert.messageText = tr("clearConfirm")
        alert.informativeText = tr("clearBody")
        alert.addButton(withTitle: tr("cancel"))
        alert.addButton(withTitle: tr("clear"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { modifyHistory { try store.clear() } }
    }

    @objc private func openSettings() { popup.close(); settings.show(preferences) }
    @objc private func togglePause() { lastChange = NSPasteboard.general.changeCount; paused.toggle(); refreshLanguage() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func saveSettings(_ value: Preferences, login: Bool) -> Bool {
        let changedKey = preferences.keyCode != value.keyCode || preferences.modifiers != value.modifiers
        if changedKey, !hotKey.register(key: value.keyCode, modifiers: value.modifiers) { showAlert("shortcutConflict"); return false }
        let oldLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        do {
            if login != oldLogin {
                do {
                    if login { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    if changedKey { _ = hotKey.register(key: preferences.keyCode, modifiers: preferences.modifiers) }
                    showAlert("loginError"); return false
                }
            }
            try store.savePreferences(value)
            preferences = value
            try store.prune(limit: value.limit)
            refreshLanguage()
            if login, SMAppService.mainApp.status == .requiresApproval { showAlert("loginApproval") }
            return true
        } catch {
            if changedKey { _ = hotKey.register(key: preferences.keyCode, modifiers: preferences.modifiers) }
            showAlert("storageError"); return false
        }
    }

    private func runSmoke() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--smoke-test"), args.indices.contains(index + 2) else { exit(2) }
        Localization.shared.language = args[index + 1] == "en" ? "en-US" : "ko-KR"
        let scenario = args.indices.contains(index + 3) ? args[index + 3] : "long"
        let output = URL(fileURLWithPath: args[index + 2])
        var items: [HistoryItem] = []
        let values = [tr("sampleShort"), tr("sampleLong"), tr("sampleMultiline")]
        for (offset, value) in values.enumerated() { items.append(HistoryItem(id: Int64(offset + 1), kind: "text", payload: Data(value.utf8))) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        Palette.accent.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 320, height: 180)).fill()
        ("Chojema CopyKeep" as NSString).draw(at: NSPoint(x: 34, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        items.append(HistoryItem(id: 4, kind: "image", payload: bitmap.representation(using: .png, properties: [:])!))
        popup.refreshLanguage()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        popup.show(items: scenario == "empty" ? [] : items, anchor: NSPoint(x: screen.midX - 210, y: screen.midY + 205), screen: screen)
        if scenario == "long" || scenario == "multiline" || scenario == "image" {
            popup.table.selectRowIndexes(IndexSet(integer: scenario == "image" ? 3 : scenario == "multiline" ? 2 : 1), byExtendingSelection: false)
        }
        var pasteIDs: [Int64] = []
        var deleteIDs: [Int64] = []
        func keyEvent(_ code: UInt16) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: popup.panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            popup.panel.sendEvent(event)
        }
        if scenario == "interactions" {
            popup.onPaste = { pasteIDs.append($0.id) }
            popup.onDelete = { deleteIDs.append($0.id) }
            guard popup.table.selectedRow == 0, !popup.showsPreview else { exit(1) }
            keyEvent(125)
            guard popup.table.selectedRow == 1, popup.showsPreview else { exit(1) }
            keyEvent(36)
            guard pasteIDs == [2] else { exit(1) }
            keyEvent(126)
            guard popup.table.selectedRow == 0, !popup.showsPreview else { exit(1) }
            popup.scheduleHover(3)
        }
        if scenario == "hover" { popup.scheduleHover(3) }
        if scenario == "settings" { popup.close(); settings.show(Preferences(language: Localization.shared.language)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                if scenario == "interactions" {
                    guard self.popup.hoverRow == 3, self.popup.table.selectedRow == 0,
                          self.popup.showsPreview, pasteIDs == [2] else { throw StoreError.invalidItem }
                    self.popup.scheduleHover(-1)
                    guard self.popup.hoverRow == -1, !self.popup.showsPreview else { throw StoreError.invalidItem }
                    self.popup.scheduleHover(3)
                    keyEvent(125)
                    guard self.popup.hoverRow == -1, self.popup.table.selectedRow == 1 else { throw StoreError.invalidItem }
                    keyEvent(51)
                    guard deleteIDs == [2] else { throw StoreError.invalidItem }
                    keyEvent(53)
                    guard !self.popup.panel.isVisible else { throw StoreError.invalidItem }
                    self.popup.show(items: items, anchor: NSPoint(x: screen.maxX, y: screen.minY), screen: screen)
                    guard self.popup.table.selectedRow == 0, !self.popup.showsPreview,
                          self.popup.panel.firstResponder === self.popup.table,
                          screen.contains(self.popup.panel.frame) else { throw StoreError.invalidItem }
                }
                if scenario == "settings", let view = self.settings.window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])!.write(to: output)
                } else { try self.popup.snapshot(to: output) }
                var report: [String: Any] = ["scenario": scenario, "language": Localization.shared.language,
                    "selectedRow": self.popup.table.selectedRow, "hoverRow": self.popup.hoverRow,
                    "preview": self.popup.showsPreview, "items": self.popup.items.count,
                    "width": self.popup.panel.frame.width, "height": self.popup.panel.frame.height]
                if scenario == "interactions" { report["interactionChecks"] = 12 }
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.deletingPathExtension().appendingPathExtension("json"))
                NSApp.terminate(nil)
            } catch { fputs("Smoke rendering failed\n", stderr); exit(1) }
        }
    }
}
