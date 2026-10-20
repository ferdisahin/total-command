// SPDX-License-Identifier: GPL-3.0-only
import Foundation

func testLocalization() throws {
    assert(L10n.resolvedLanguage(preference: "en", preferredLanguages: ["tr-TR"]) == "en")
    assert(L10n.resolvedLanguage(preference: "tr", preferredLanguages: ["en-US"]) == "tr")
    assert(L10n.resolvedLanguage(preference: "system", preferredLanguages: ["tr-TR", "en-US"]) == "tr")
    assert(L10n.resolvedLanguage(preference: "system", preferredLanguages: ["en_GB", "tr"]) == "en")
    assert(L10n.resolvedLanguage(preference: "system", preferredLanguages: ["de-DE", "tr"]) == "tr")
    assert(L10n.resolvedLanguage(preference: "invalid", preferredLanguages: []) == "en")
    let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    let enURL = resources.appendingPathComponent("en.lproj/Localizable.strings")
    let trURL = resources.appendingPathComponent("tr.lproj/Localizable.strings")
    let en = try PropertyListSerialization.propertyList(from: Data(contentsOf: enURL), format: nil) as! [String: String]
    let tr = try PropertyListSerialization.propertyList(from: Data(contentsOf: trURL), format: nil) as! [String: String]
    assert(Set(en.keys) == Set(tr.keys) && en.count >= 290)
    let pattern = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
    func placeholders(_ text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }.sorted()
    }
    for key in en.keys {
        assert(!en[key]!.isEmpty && !tr[key]!.isEmpty)
        assert(tr[key] == key)
        assert(placeholders(key) == placeholders(en[key]!), "Placeholder mismatch: \(key)")
    }
    let calls = try NSRegularExpression(pattern: #"\bL\("((?:\\.|[^"\\])*)""#)
    for file in try FileManager.default.contentsOfDirectory(at: resources.deletingLastPathComponent().appendingPathComponent("Sources"), includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in calls.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let literal = String(source[Range(match.range(at: 1), in: source)!])
            let key = try JSONDecoder().decode(String.self, from: Data(("\"" + literal + "\"").utf8))
            assert(en[key] != nil && tr[key] != nil, "Missing translation: \(key)")
        }
    }
    let english = Bundle(path: resources.appendingPathComponent("en.lproj").path)!
    let turkish = Bundle(path: resources.appendingPathComponent("tr.lproj").path)!
    assert(L10n.render("Ayarlar", arguments: [], bundle: english) == "Settings")
    assert(L10n.render("Ayarlar", arguments: [], bundle: turkish) == "Ayarlar")
    assert(L10n.render("Klasör bulunamadı: {0}", arguments: ["/Türkçe/{1}/100%.txt"], bundle: english) == "Folder not found: /Türkçe/{1}/100%.txt")
    assert(L10n.render("{0} çalışan · {1} bekleyen · {2} hatalı{3}", arguments: ["1", "2", "3", " · Queue paused"], bundle: english) == "1 running · 2 pending · 3 failed · Queue paused")
    assert(L10n.render("unknown {0}", arguments: ["x"], bundle: english) == "unknown x")
    assert(L10n.render("unknown {0}", arguments: [], bundle: nil) == "unknown {0}")
    print("PASS: language resolution, complete EN/TR catalogs, placeholders, resource loading and literal file names")
}
