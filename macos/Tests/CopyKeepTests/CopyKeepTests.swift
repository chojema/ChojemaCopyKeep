import Testing
import AppKit
import Carbon
@testable import CopyKeep

@Suite(.serialized)
struct CopyKeepTests {
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
