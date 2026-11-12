import Foundation

private struct LocalizationCatalog: Decodable {
    struct Entry: Decodable {
        struct Localization: Decodable {
            struct StringUnit: Decodable { let value: String }
            let stringUnit: StringUnit
        }
        let localizations: [String: Localization]
    }
    let sourceLanguage: String
    let strings: [String: Entry]
}

private let localizationCatalog: LocalizationCatalog = {
    guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let catalog = try? JSONDecoder().decode(LocalizationCatalog.self, from: data) else {
        fatalError("Localizable.json is missing or invalid")
    }
    return catalog
}()

private var preferredLocalization: String {
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? localizationCatalog.sourceLanguage
    return preferred.hasPrefix("zh") ? "zh-Hans" : localizationCatalog.sourceLanguage
}

/// Resolves every user-facing string from the single Localizable.json catalog.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    guard let entry = localizationCatalog.strings[key] else { return key }
    let format = entry.localizations[preferredLocalization]?.stringUnit.value
        ?? entry.localizations[localizationCatalog.sourceLanguage]?.stringUnit.value
        ?? key
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale.current, arguments: arguments)
}
