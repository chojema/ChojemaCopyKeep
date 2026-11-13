import Testing
import AppKit
import Carbon
import SQLite3
@testable import CopyKeep

@Suite(.serialized)
struct CopyKeepTests {
    @Test func testUpdateVersionsAndReleaseLocations() throws {
        expectEqual(ReleaseVersion("0.3.0")?.text, "0.3.0")
        expectEqual(ReleaseVersion("10.20.65535")?.components, [10, 20, 65535])
        expectTrue(try unwrap(ReleaseVersion("0.10.0")) > unwrap(ReleaseVersion("0.9.9")))
        expectTrue(try unwrap(ReleaseVersion("1.0.0")) > unwrap(ReleaseVersion("0.99.99")))
        expectFalse(try unwrap(ReleaseVersion("0.3.0")) > unwrap(ReleaseVersion("0.3.0")))
        for value in ["", "1", "1.2", "1.2.3.4", "1..3", "-1.2.3", "1.2.3-beta", "1.2.3-macos",
                      "1.2.3\n", " 1.2.3", "01.2.3", "65536.0.0", "9999999999.0.0", "1.2.x"] {
            expectNil(ReleaseVersion(value))
        }
        let prefix = "https://github.com/chojema/ChojemaCopyKeep/releases/tag/v"
        expectEqual(ReleaseVersion.fromLocation(prefix + "0.3.0"), ReleaseVersion("0.3.0"))
        expectEqual(ReleaseVersion.fromLocation("/chojema/ChojemaCopyKeep/releases/tag/v0.3.0"), ReleaseVersion("0.3.0"))
        for value in [prefix + "1.0.0-macos", prefix + "1.0.0?test",
                      prefix.replacingOccurrences(of: "https:", with: "http:") + "1.0.0",
                      prefix.replacingOccurrences(of: "github.com", with: "github.com.evil") + "1.0.0",
                      prefix.replacingOccurrences(of: "/chojema/", with: "/other/") + "1.0.0"] {
            expectNil(ReleaseVersion.fromLocation(value))
        }
    }

    @Test @MainActor func testUpdateAlertsInBothLanguages() {
        let original = Localization.shared.language
        defer { Localization.shared.language = original }
        for language in Localization.languages {
            Localization.shared.language = language
            let available = makeUpdateAlert(current: "0.3.0", latest: ReleaseVersion("0.4.0"))
            expectEqual(available.buttons.count, 2)
            expectEqual(available.buttons[0].title, tr("cancel"))
            expectTrue(available.informativeText.contains("0.3.0") && available.informativeText.contains("0.4.0"))
            for version in ["0.3.0", "0.2.0"] { expectEqual(makeUpdateAlert(current: "0.3.0", latest: ReleaseVersion(version)).buttons.count, 1) }
            expectEqual(makeUpdateAlert(current: "0.3.0", latest: nil).informativeText, tr("updateError"))
            expectEqual(makeUpdateAlert(current: "bad", latest: ReleaseVersion("0.4.0")).informativeText, tr("updateError"))
        }
    }

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopyKeepTests-" + UUID().uuidString)

    private func text(_ value: String) -> Data { Data(value.utf8) }

    @Test func testDefaultsAndPersistence() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: HistoryStore? = try HistoryStore(directory: directory)
        expectEqual(try store!.loadPreferences(), Preferences())
        expectEqual(try store!.loadPreferences().language, "ko-KR")
        expectEqual(try store!.loadPreferences().limit, 200)
        var preference = Preferences()
        preference.language = "en-US"; preference.limit = 50; preference.moveUsed = false
        preference.keyCode = 0; preference.modifiers = UInt32(optionKey | shiftKey)
        try store!.savePreferences(preference)
        try store!.add(kind: "text", payload: text("한글\nEnglish\t🙂"), limit: 50)
        store = nil
        let restored = try HistoryStore(directory: directory)
        expectEqual(try restored.loadPreferences(), preference)
        expectEqual(try restored.list().first?.text, "한글\nEnglish\t🙂")
    }

    @Test func testInvalidLanguageFallsBackAndLimitClamps() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        var preference = Preferences(); preference.language = "fr-FR"; preference.limit = 5000
        try store.savePreferences(preference)
        expectEqual(try store.loadPreferences().language, "ko-KR")
        expectEqual(try store.loadPreferences().limit, 1000)
    }

    @Test func testDuplicateAndUseOrderingAndDeletion() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try store.add(kind: "text", payload: text("one"), limit: 200)
        try store.add(kind: "text", payload: text("two"), limit: 200)
        let id = try unwrap(store.list().last?.id)
        expectEqual(try store.list().map(\.text), ["two", "one"])
        try store.add(kind: "text", payload: text("one"), limit: 200)
        expectEqual(try store.list().map(\.text), ["one", "two"])
        expectEqual(try store.list().first?.id, id)
        try store.touch(try unwrap(store.list().last?.id))
        expectEqual(try store.list().map(\.text), ["two", "one"])
        try store.delete(id)
        expectEqual(try store.list().map(\.text), ["two"])
        try store.clear()
        expectTrue(try store.list().isEmpty)
    }

    @Test func testHistoryLimitAndByteBudget() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        for number in 0..<15 { try store.add(kind: "text", payload: text("item \(number)"), limit: 10) }
        expectEqual(try store.list().count, 10)
        expectEqual(try store.list().last?.text, "item 5")
        try store.clear()
        let block = Data(repeating: 65, count: HistoryStore.maxItemBytes - 1)
        for number in 0..<9 { try store.add(kind: "text", payload: block + text(String(number)), limit: 200) }
        let items = try store.list()
        expectEqual(items.count, 8)
        expectAtMost(items.reduce(0) { $0 + $1.payload.count }, HistoryStore.maxTotalBytes)
        expectEqual(items.first?.payload.last, Character("8").asciiValue)
    }

    @Test func testRejectInvalidPayloadWithoutRemovingHistory() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try store.add(kind: "text", payload: text("keep"), limit: 200)
        expectThrows(try store.add(kind: "file", payload: text("invalid"), limit: 200))
        expectThrows(try store.add(kind: "text", payload: Data(), limit: 200))
        expectThrows(try store.add(kind: "text", payload: Data([0xff]), limit: 200))
        expectThrows(try store.add(kind: "text", payload: Data(repeating: 65, count: HistoryStore.maxItemBytes + 1), limit: 200))
        expectEqual(try store.list().first?.text, "keep")
    }

    @Test func testPrivateFilesystemPermissions() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        try store.add(kind: "text", payload: text("synthetic"), limit: 200)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        let dbPermissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.db").path)[.posixPermissions] as? Int
        expectEqual(permissions, 0o700)
        expectEqual(dbPermissions, 0o600)
    }

    @Test func testLocalizationKeysAndFormatPlaceholders() {
        let localization = Localization()
        expectFalse(localization.keys("ko-KR").isEmpty)
        expectEqual(localization.keys("ko-KR"), localization.keys("en-US"))
        for key in localization.keys("ko-KR") {
            localization.language = "ko-KR"; let korean = localization.text(key)
            localization.language = "en-US"; let english = localization.text(key)
            expectFalse(korean.isEmpty, key); expectFalse(english.isEmpty, key)
            expectEqual(korean.components(separatedBy: "%d").count, english.components(separatedBy: "%d").count, key)
        }
        localization.language = "ko-KR"; expectEqual(localization.text("settings"), "설정")
        localization.language = "en-US"; expectEqual(localization.text("settings"), "Settings")
    }

    @Test func testSnippetsStaySeparateAndPersist() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: HistoryStore? = try HistoryStore(directory: directory)
        try store!.add(kind: "text", payload: text("original history"), limit: 200)
        let id = try store!.saveSnippet(title: "인사 Greeting", body: "첫 줄\r\nSecond line")
        expectEqual(try store!.snippets(matching: "gReEt").first?.id, id)
        expectEqual(try store!.snippets(matching: "SECOND").first?.text, "첫 줄\r\nSecond line")
        expectEqual(try store!.snippets(matching: "첫 줄").count, 1)
        expectTrue(try store!.snippets(matching: "%").isEmpty)
        expectTrue(try store!.snippets(matching: "' OR 1=1 --").isEmpty)
        expectTrue(try store!.snippets().first?.isSnippet == true)
        try store!.saveSnippet(id: id, title: "Edited", body: "수정한 본문")
        expectEqual(try store!.snippets().count, 1)
        for number in 0..<15 { try store!.add(kind: "text", payload: text("item \(number)"), limit: 10) }
        try store!.clear()
        expectEqual(try store!.snippets().first?.title, "Edited")
        store = nil
        let restored = try HistoryStore(directory: directory)
        expectEqual(try restored.snippets().first?.text, "수정한 본문")
        try restored.add(kind: "text", payload: text("keep history"), limit: 200)
        try restored.deleteSnippet(id)
        expectTrue(try restored.snippets().isEmpty)
        expectEqual(try restored.list().first?.text, "keep history")
    }

    @Test func testInvalidSnippetEditsPreserveOriginal() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let id = try store.saveSnippet(title: "Keep", body: "Keep body")
        for title in ["", " ", "two\nlines", "tab\t", String(repeating: "a", count: 81), "bad\0"] {
            expectThrows(try store.saveSnippet(id: id, title: title, body: "discard"))
        }
        for body in ["", " \n", String(repeating: "a", count: 65537), "bad\0"] {
            expectThrows(try store.saveSnippet(id: id, title: "discard", body: body))
        }
        expectThrows(try store.saveSnippet(id: 999999, title: "missing", body: "body"))
        expectEqual(try store.snippets().first?.title, "Keep")
        expectEqual(try store.snippets().first?.text, "Keep body")
    }

    @Test func testTextReplacementRulesAndLegacyMigration() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var db: OpaquePointer?
        expectEqual(sqlite3_open(directory.appendingPathComponent("history.db").path, &db), SQLITE_OK)
        expectEqual(sqlite3_exec(db, "CREATE TABLE snippets(id INTEGER PRIMARY KEY,title TEXT NOT NULL,payload BLOB NOT NULL); INSERT INTO snippets VALUES(1,'Legacy',X'6B656570');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var store: HistoryStore? = try HistoryStore(directory: directory)
        let legacy: Int64 = 1
        expectEqual(try store!.snippets().first?.text, "keep")
        let id = try store!.saveSnippet(title: "Address", body: "서울\nSeoul 😀", abbreviation: ";;addr")
        expectEqual(try store!.snippets(matching: ";;addr").first?.id, id)
        for abbreviation in ["x", "한글", "a b", String(repeating: "x", count: 65), ";;addr", ";;ad", ";;addr2"] {
            expectThrows(try store!.saveSnippet(title: "Bad", body: "discard", abbreviation: abbreviation))
        }
        try store!.saveSnippet(id: id, title: "Address", body: "Updated", abbreviation: ";;addr")
        store = nil; store = try HistoryStore(directory: directory)
        expectEqual(try store!.snippets().first?.abbreviation, ";;addr")
        expectEqual(try store!.snippets().first(where: { $0.id == legacy })?.abbreviation, "")
        try store!.clear()
        expectEqual(try store!.snippets().count, 2)
    }

    @Test func testReplacementMatcher() {
        var matcher = ReplacementMatcher(rules: [";;addr": "서울\nSeoul 😀", "sig": "Signature"])
        for character in ";;add" { expectTrue(matcher.append(String(character)) == nil) }
        expectEqual(matcher.append("r")?.1, "서울\nSeoul 😀")
        matcher.reset()
        for character in "design" { expectTrue(matcher.append(String(character)) == nil) }
        matcher.reset()
        for character in "si" { expectTrue(matcher.append(String(character)) == nil) }
        expectEqual(matcher.append("g")?.1, "Signature")
        matcher.reset()
        for character in ";;ADDR" { expectTrue(matcher.append(String(character)) == nil) }
        _ = matcher.append("한"); expectEqual(matcher.buffer, "")
        for _ in 0..<200 { _ = matcher.append("x") }
        expectEqual(matcher.buffer.count, 65)
        _ = matcher.append("\u{7f}"); expectEqual(matcher.buffer, "")
    }

    @Test func testShortcutValidation() {
        expectTrue(ShortcutKeys.valid(key: 6, modifiers: UInt32(controlKey | shiftKey)))
        expectTrue(ShortcutKeys.valid(key: 0, modifiers: UInt32(optionKey)))
        expectFalse(ShortcutKeys.valid(key: 6, modifiers: UInt32(shiftKey)))
        expectFalse(ShortcutKeys.valid(key: 999, modifiers: UInt32(controlKey)))
        expectEqual(ShortcutKeys.label(Preferences()), "⌃⇧Z")
    }

    @Test func testScreenClampingIncludingNegativeCoordinates() {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: -1920, y: -200, width: 1920, height: 1080), NSRect(x: 0, y: 0, width: 640, height: 360)] {
            for anchor in [NSPoint(x: screen.minX, y: screen.minY), NSPoint(x: screen.maxX, y: screen.maxY), NSPoint(x: screen.midX, y: screen.midY)] {
                let frame = PopupPlacement.frame(anchor: anchor, size: NSSize(width: 800, height: 410), screen: screen)
                expectAtLeast(frame.minX, screen.minX)
                expectAtLeast(frame.minY, screen.minY)
                expectAtMost(frame.maxX, screen.maxX)
                expectAtMost(frame.maxY, screen.maxY)
            }
        }
    }

    @Test func testNamedPasteboardTextAndExclusions() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        expectTrue(board.setString("synthetic clipboard", forType: .string))
        expectEqual(ClipboardContent.read(board)?.0, "text")
        expectEqual(ClipboardContent.read(board)?.1, text("synthetic clipboard"))
        for type in ClipboardContent.excluded + [NSPasteboard.PasteboardType.fileURL.rawValue] {
            board.clearContents()
            board.setString("private synthetic value", forType: .string)
            board.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            expectNil(ClipboardContent.read(board), type)
        }
    }

    @Test func testImageNormalizationAndPreviewDecisions() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try unwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try unwrap(image.representation(using: .png, properties: [:]))
        let normalized = try unwrap(ClipboardContent.normalizedImage(png))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        expectTrue(board.setData(png, forType: .png))
        expectEqual(ClipboardContent.read(board)?.0, "image")
        expectNotNil(NSImage(data: normalized))
        expectNil(ClipboardContent.normalizedImage(text("not an image")))
        expectTrue(ClipboardContent.needsPreview(HistoryItem(id: 1, kind: "image", payload: png)))
        for value in ["line\nbreak", "a\tb", String(repeating: "long ", count: 100)] {
            expectTrue(ClipboardContent.needsPreview(HistoryItem(id: 1, kind: "text", payload: text(value))))
        }
        expectFalse(ClipboardContent.needsPreview(HistoryItem(id: 1, kind: "text", payload: text("short"))))
    }
}

private func expectEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: String = "") {
    do { let a = try left(); let b = try right(); #expect(a == b, Comment(rawValue: message)) }
    catch { Issue.record(error) }
}
private func expectAtMost<T: Comparable>(_ left: T, _ right: T) { #expect(left <= right) }
private func expectAtLeast<T: Comparable>(_ left: T, _ right: T) { #expect(left >= right) }
private func expectTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "") {
    do { #expect(try value(), Comment(rawValue: message)) } catch { Issue.record(error) }
}
private func expectFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "") {
    do { #expect(try !value(), Comment(rawValue: message)) } catch { Issue.record(error) }
}
private func expectNil<T>(_ value: T?, _ message: String = "") { #expect(value == nil, Comment(rawValue: message)) }
private func expectNotNil<T>(_ value: T?) { #expect(value != nil) }
private func expectThrows(_ action: @autoclosure () throws -> Any) {
    do { _ = try action(); Issue.record("Expected an error") } catch { }
}
private func unwrap<T>(_ value: T?) throws -> T { try #require(value) }
