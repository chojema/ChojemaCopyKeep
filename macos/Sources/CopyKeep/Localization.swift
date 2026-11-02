import Foundation

final class Localization {
    static let shared = Localization()
    var language = "ko-KR"
    static let languages = ["ko-KR", "en-US"]
    private var tables: [String: [String: String]] = [:]

    init() {
        for language in Self.languages {
            let folder = language == "en-US" ? "en" : "ko"
            let url = Bundle.module.url(forResource: "Localizable", withExtension: "strings",
                                        subdirectory: "Resources/\(folder).lproj")!
            tables[language] = NSDictionary(contentsOf: url) as? [String: String] ?? [:]
        }
    }

    func text(_ key: String) -> String { tables[language]?[key] ?? tables["ko-KR"]?[key] ?? key }
    func keys(_ language: String) -> Set<String> { Set(tables[language]?.keys.map { $0 } ?? []) }
}

func tr(_ key: String) -> String { Localization.shared.text(key) }
