// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum L10n {
    // Capture once per launch so open windows, jobs and menus use one language.
    static let activeLanguage = resolvedLanguage(preference: Prefs.string("appLanguage"), preferredLanguages: Locale.preferredLanguages)
    private static let activeBundle: Bundle? = languageBundle(activeLanguage, in: .main)
    private static let placeholders = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static func resolvedLanguage(preference: String, preferredLanguages: [String]) -> String {
        if preference == "tr" || preference == "en" { return preference }
        for language in preferredLanguages {
            let code = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "tr" { return "tr" }
            if code == "en" { return "en" }
        }
        return "en"
    }
    static func languageBundle(_ language: String, in bundle: Bundle) -> Bundle? {
        guard ["tr", "en"].contains(language), let path = bundle.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
    static func render(_ key: String, arguments: [String], bundle: Bundle?) -> String {
        let template = bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        guard !arguments.isEmpty else { return template }
        let matches = placeholders.matches(in: template, range: NSRange(template.startIndex..., in: template))
        var result = template
        // Replace backwards, never interpreting braces in file names or other arguments.
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: template), let index = Int(template[numberRange]), arguments.indices.contains(index), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
    static func text(_ key: String, arguments: [String]) -> String { render(key, arguments: arguments, bundle: activeBundle) }
}

func L(_ key: String, _ arguments: Any...) -> String {
    L10n.text(key, arguments: arguments.map { String(describing: $0) })
}
