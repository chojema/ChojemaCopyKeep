import AppKit
import ApplicationServices
import ServiceManagement

final class AppController: NSObject, NSApplicationDelegate {
    var store: HistoryStore!
    var preferences = Preferences()
    let popup = PopupController()
    let settings = SettingsController()
    let snippetEditor = SnippetEditorController()
    private let hotKey = HotKey()
    private var status: NSStatusItem?
    private var timer: Timer?
    private var lastChange = 0
    private var paused = false
    private var target: NSRunningApplication?
    private var pastePending = false
    private var collectionErrorShown = false
    private var checkingUpdate = false
    private let updateChecker = UpdateChecker()

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
        popup.onDelete = { [weak self] item in self?.deleteItem(item) }
        popup.onReload = { [weak self] in
            do { try self?.reloadPopup() } catch { showAlert("storageError") }
        }
        popup.onNewSnippet = { [weak self] in self?.editSnippet(nil) }
        popup.onEditSnippet = { [weak self] in self?.editSnippet($0) }
        snippetEditor.onSave = { [weak self] id, title, body in
            guard let self else { return false }
            do {
                let saved = try self.store.saveSnippet(id: id, title: title, body: body)
                self.popup.selectSource(true); self.popup.search.stringValue = ""
                try self.reloadPopup()
                if let row = self.popup.items.firstIndex(where: { $0.id == saved }) {
                    self.popup.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                return true
            } catch StoreError.invalidItem { showAlert("invalidSnippet"); return false }
            catch { showAlert("storageError"); return false }
        }
        snippetEditor.onFinish = { [weak self] in self?.popup.reopen() }
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
        snippetEditor.refreshLanguage()
        let menu = NSMenu()
        for (key, action) in [("history", #selector(openHistory)), ("settings", #selector(openSettings)),
                              (paused ? "resume" : "pause", #selector(togglePause)),
                              (checkingUpdate ? "updateChecking" : "checkUpdate", #selector(checkForUpdates)), ("quit", #selector(quit))] {
            if key == "quit" { menu.addItem(.separator()) }
            let title = key == "history" ? tr(key) + "  " + ShortcutKeys.label(preferences) : tr(key)
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if action == #selector(checkForUpdates) { item.isEnabled = !checkingUpdate }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
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
            if popup.panel.isVisible && !popup.showingSnippets { popup.reload(try store.list()) }
        } catch {
            // Stop collection after a storage failure; retry only when the user resumes it.
            paused = true; refreshLanguage()
            if !collectionErrorShown { collectionErrorShown = true; showAlert("collectionError") }
        }
    }

    @objc func openHistory() {
        guard store != nil, !pastePending, !snippetEditor.window.isVisible else { return }
        if popup.panel.isVisible { popup.close(); return }
        target = NSWorkspace.shared.frontmostApplication
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier { target = nil }
        let anchor = caretPosition() ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        do { popup.show(items: try popupItems(), anchor: anchor, screen: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)) }
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
                if self.preferences.moveUsed && !item.isSnippet {
                    do { try self.store.touch(item.id) } catch { showAlert("storageError") }
                }
            } else if Date() >= deadline {
                timer.invalidate(); self.pastePending = false; showAlert("pasteError")
            }
        }
    }

    private func modifyHistory(_ action: () throws -> Void) {
        do { try action(); try reloadPopup() } catch { showAlert("storageError") }
    }

    private func popupItems() throws -> [HistoryItem] {
        try popup.showingSnippets ? store.snippets(matching: popup.search.stringValue) : store.list()
    }
    private func reloadPopup() throws { popup.reload(try popupItems()) }

    private func editSnippet(_ item: HistoryItem?) {
        if let item, item.kind != "text" || item.text.utf16.count > 65536 { showAlert("invalidSnippet"); return }
        popup.close(); snippetEditor.show(item)
    }

    private func deleteItem(_ item: HistoryItem) {
        if item.isSnippet {
            popup.close()
            let alert = NSAlert(); alert.messageText = tr("deleteSnippet"); alert.informativeText = tr("deleteSnippetBody")
            alert.addButton(withTitle: tr("cancel")); alert.addButton(withTitle: tr("delete"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn { modifyHistory { try store.deleteSnippet(item.id) } }
            popup.reopen()
        } else { modifyHistory { try store.delete(item.id) } }
    }

    private func clearHistory() {
        guard !popup.showingSnippets else { return }
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

    @objc private func checkForUpdates() {
        guard !checkingUpdate else { return }
        checkingUpdate = true
        refreshLanguage()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latest = try? await self.updateChecker.latest()
            self.checkingUpdate = false
            self.refreshLanguage()
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let alert = makeUpdateAlert(current: current, latest: latest)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn, !NSWorkspace.shared.open(UpdateChecker.releasePage) {
                showAlert("updateOpenError")
            }
        }
    }

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
        if args.contains("--smoke-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--smoke-light") { NSApp.appearance = NSAppearance(named: .aqua) }
        guard let index = args.firstIndex(of: "--smoke-test"), args.indices.contains(index + 2) else { exit(2) }
        Localization.shared.language = args[index + 1] == "en" ? "en-US" : "ko-KR"
        let scenario = args.indices.contains(index + 3) ? args[index + 3] : "long"
        let output = URL(fileURLWithPath: args[index + 2])
        if scenario.hasPrefix("update-") {
            Task { @MainActor in
                let latest: ReleaseVersion?
                if scenario == "update-live" { latest = try? await self.updateChecker.latest() }
                else { latest = scenario == "update-error" ? nil : ReleaseVersion(scenario == "update-available" ? "0.4.0" : "0.3.0") }
                let alert = makeUpdateAlert(current: "0.3.0", latest: latest)
                alert.layout()
                alert.window.center()
                alert.window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        guard let view = alert.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
                        let report: [String: Any] = ["scenario": scenario, "language": Localization.shared.language,
                            "latest": latest?.text ?? "", "body": alert.informativeText, "buttons": alert.buttons.map(\.title)]
                        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                            .write(to: output.deletingPathExtension().appendingPathExtension("json"))
                        if scenario == "update-live", latest == nil { exit(1) }
                        NSApp.terminate(nil)
                    } catch { exit(1) }
                }
            }
            return
        }
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
        let snippetScenario = ["snippets", "snippet-editor", "snippet-interactions"].contains(scenario)
        var smokeDirectory: URL?
        var snippetChecks = 0
        if snippetScenario {
            do {
                let directory = output.deletingLastPathComponent().appendingPathComponent("snippets-" + UUID().uuidString)
                smokeDirectory = directory; store = try HistoryStore(directory: directory)
                preferences.language = Localization.shared.language
                try store.savePreferences(preferences)
                for item in items.reversed() { try store.add(kind: item.kind, payload: item.payload, limit: 200) }
                items = try store.list(); wireActions()
            } catch { fputs("Smoke storage failed\n", stderr); exit(1) }
        }
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
        if snippetScenario {
            do {
                func check(_ value: Bool) throws { guard value else { throw StoreError.invalidItem }; snippetChecks += 1 }
                let original = try store.list().map(\.text)
                popup.editSnippet()
                try check(snippetEditor.window.isVisible && snippetEditor.body.string == items[0].text)
                snippetEditor.saveChanges()
                try check(popup.showingSnippets && popup.items.count == 1 && popup.items[0].isSnippet && popup.items[0].text == items[0].text)
                popup.newSnippet()
                snippetEditor.titleField.stringValue = "인사 Greeting"
                snippetEditor.body.string = "첫 번째 줄\nSecond line"
                snippetEditor.saveChanges()
                try check(try store.snippets().count == 2)
                popup.editSnippet(); snippetEditor.body.string = "Discard edit"; snippetEditor.close()
                try check(try store.snippets().first?.text == "첫 번째 줄\nSecond line")
                popup.editSnippet(); snippetEditor.titleField.stringValue = "수정된 인사 Greeting"
                snippetEditor.body.string = "수정한 첫 줄\nSecond line"; snippetEditor.saveChanges()
                try check(try store.snippets().count == 2 && store.snippets().first?.title == "수정된 인사 Greeting")
                popup.search.stringValue = "second LINE"; popup.searchChanged()
                try check(popup.items.count == 1 && popup.showsPreview)
                popup.search.stringValue = "없는 결과"; popup.searchChanged(); try check(popup.items.isEmpty)
                popup.search.stringValue = "Greeting"; popup.searchChanged()
                try check(popup.items.count == 1)
                popup.onDelete = { deleteIDs.append($0.id) }; popup.onPaste = { pasteIDs.append($0.id) }
                popup.panel.makeFirstResponder(popup.search); keyEvent(51)
                try check(deleteIDs.isEmpty)
                keyEvent(125); try check(popup.panel.firstResponder === popup.table)
                keyEvent(36); try check(pasteIDs.count == 1 && pasteIDs[0] == popup.items[0].id)
                do { try store.saveSnippet(title: "", body: "discard"); throw StoreError.database }
                catch StoreError.invalidItem { snippetChecks += 1 }
                do { try store.saveSnippet(title: "too large", body: String(repeating: "x", count: 65537)); throw StoreError.database }
                catch StoreError.invalidItem { snippetChecks += 1 }
                try check(try store.list().map(\.text) == original)
                try store.prune(limit: 10); try store.clear()
                try check(try store.snippets().count == 2 && store.loadPreferences() == preferences)
                store = nil; store = try HistoryStore(directory: smokeDirectory!)
                try check(try store.snippets().count == 2)
                popup.search.stringValue = "Greeting"; popup.searchChanged()
                if scenario == "snippet-editor" { popup.editSnippet() }
            } catch { fputs("Snippet interaction checks failed\n", stderr); exit(1) }
        }
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
                } else if scenario == "snippet-editor", let view = self.snippetEditor.window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])!.write(to: output)
                } else { try self.popup.snapshot(to: output) }
                var report: [String: Any] = ["scenario": scenario, "language": Localization.shared.language,
                    "selectedRow": self.popup.table.selectedRow, "hoverRow": self.popup.hoverRow,
                    "preview": self.popup.showsPreview, "items": self.popup.items.count,
                    "width": self.popup.panel.frame.width, "height": self.popup.panel.frame.height,
                    "appearance": NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? ""]
                if scenario == "interactions" { report["interactionChecks"] = 12 }
                if snippetScenario { report["snippetChecks"] = snippetChecks }
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.deletingPathExtension().appendingPathExtension("json"))
                if let smokeDirectory { self.store = nil; try FileManager.default.removeItem(at: smokeDirectory) }
                NSApp.terminate(nil)
            } catch { fputs("Smoke rendering failed\n", stderr); exit(1) }
        }
    }
}
