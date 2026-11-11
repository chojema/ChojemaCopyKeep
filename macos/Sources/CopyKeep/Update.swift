import AppKit

struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 5,
                  part.count == 1 || part.first != "0",
                  part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let number = Int(part), number <= 65535 else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    var text: String { components.map(String.init).joined(separator: ".") }
    static func < (left: Self, right: Self) -> Bool { left.components.lexicographicallyPrecedes(right.components) }

    static func fromLocation(_ location: String) -> Self? {
        for prefix in ["https://github.com/chojema/ChojemaCopyKeep/releases/tag/v", "/chojema/ChojemaCopyKeep/releases/tag/v"] {
            if location.hasPrefix(prefix) { return Self(String(location.dropFirst(prefix.count))) }
        }
        return nil
    }
}

final class UpdateChecker: NSObject, URLSessionTaskDelegate {
    static let releasePage = URL(string: "https://github.com/chojema/ChojemaCopyKeep/releases/latest")!

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func latest() async throws -> ReleaseVersion {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: Self.releasePage, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "HEAD"
        request.setValue("ChojemaCopyKeep", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 302,
              let location = response.value(forHTTPHeaderField: "Location"),
              let version = ReleaseVersion.fromLocation(location) else { throw URLError(.badServerResponse) }
        return version
    }
}

func makeUpdateAlert(current: String, latest: ReleaseVersion?) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Chojema CopyKeep"
    guard let latest, let running = ReleaseVersion(current) else {
        alert.informativeText = tr("updateError")
        alert.addButton(withTitle: tr("ok"))
        return alert
    }
    let newer = latest > running
    alert.informativeText = tr(newer ? "updateAvailable" : "updateCurrent") + "\n\n" +
        tr("currentVersion") + " " + current + "\n" + tr("latestVersion") + " " + latest.text
    alert.addButton(withTitle: tr(newer ? "cancel" : "ok"))
    if newer { alert.addButton(withTitle: tr("openRelease")) }
    return alert
}
