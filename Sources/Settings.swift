// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa
import UniformTypeIdentifiers

enum Prefs {
    static var store = UserDefaults.standard
    static let defaults: [String: Any] = [
        "appLanguage": "system", "updateInterval": 0, "updatePreviews": false,
        "commandBar": true, "theme": "system", "fontSize": 12, "rowHeight": 24, "foldersFirst": true,
        "extensions": true, "thumbnails": true, "dateStyle": "short", "defaultView": 0,
        "hiddenDefault": false, "restoreTabs": true, "confirmTrash": true, "confirmMove": false,
        "collision": "ask", "archiveFormat": "zip", "browseArchives": true,
        "searchHidden": false, "searchLimit": 1000, "functionKeys": true, "spacePreview": true,
        "editor": "/System/Applications/TextEdit.app",
        "leftStart": FileManager.default.homeDirectoryForCurrentUser.path,
        "rightStart": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path,
        "keyF3": "preview", "keyF4": "edit", "keyF5": "copy", "keyF6": "move", "keyF7": "folder", "keyF8": "trash"
    ]
    static func register() { store.register(defaults: defaults) }
    static func bool(_ key: String) -> Bool { store.bool(forKey: key) }
    static func int(_ key: String) -> Int { store.integer(forKey: key) }
    static func string(_ key: String) -> String { store.string(forKey: key) ?? "" }
    static func set(_ key: String, _ value: Any) { store.set(value, forKey: key) }
    static func applyAppearance() { switch string("theme") { case "light": NSApp.appearance = NSAppearance(named: .aqua); case "dark": NSApp.appearance = NSAppearance(named: .darkAqua); default: NSApp.appearance = nil } }
}
final class SettingsController: NSWindowController, NSTextFieldDelegate {
    var changed: (() -> Void)?
    var checkForUpdates: (() -> Void)?
    private var updateButton: NSButton?
    private var updateStatus: NSTextField?
    var updateMessage = "" { didSet { updateStatus?.stringValue = updateMessage } }
    var checkingUpdates = false { didSet { updateButton?.isEnabled = !checkingUpdates } }
    private var controls: [String: NSControl] = [:]
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Total Command — Ayarlar"); window.isReleasedWhenClosed = false
        super.init(window: window); build(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func build() {
        controls = [:]
        let tabs = NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints = false
        func page(_ title: String, _ description: String) -> NSStackView {
            let item = NSTabViewItem(identifier: title); item.label = title; let view = NSView(); item.view = view; tabs.addTabViewItem(item)
            let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 22, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: description); detail.textColor = .secondaryLabelColor; detail.font = .systemFont(ofSize: 12)
            let stack = NSStackView(views: [heading, detail]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22)])
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return stack
        }
        let general = page(L("Genel"), L("Ayarlar otomatik kaydedilir. Başlangıç klasörleri bir sonraki açılışta kullanılır; sekmeleri geri yükleme açıksa son sekmeler önceliklidir."))
        popup(L("Uygulama dili"), "appLanguage", [(L("macOS ile aynı"), "system"), ("Türkçe", "tr"), ("English", "en")], general)
        let languageNote = NSTextField(wrappingLabelWithString: L("Dil değişiklikleri uygulamayı yeniden açtığınızda uygulanır.")); languageNote.font = .systemFont(ofSize: 12); languageNote.textColor = .secondaryLabelColor; languageNote.widthAnchor.constraint(equalToConstant: 720).isActive = true; general.addArrangedSubview(languageNote)
        check(L("Son açık sekmeleri geri yükle"), "restoreTabs", general)
        path(L("Sol başlangıç klasörü"), "leftStart", general)
        path(L("Sağ başlangıç klasörü"), "rightStart", general)
        path(L("Metin düzenleyici"), "editor", general)
        popup(L("Varsayılan görünüm"), "defaultView", [(L("Ayrıntılı liste"), 0), (L("Büyük simgeler"), 1)], general)
        let view = page(L("Görünüm"), L("Değişiklikler iki panele anında uygulanır. Liste sütunlarına tıklayarak sıralamayı değiştirebilirsiniz."))
        popup(L("Tema"), "theme", [(L("macOS ile aynı"), "system"), (L("Açık"), "light"), (L("Koyu"), "dark")], view)
        popup(L("Yazı boyutu"), "fontSize", [(L("11 punto"), 11), (L("12 punto"), 12), (L("13 punto"), 13), (L("14 punto"), 14), (L("15 punto"), 15)], view)
        popup(L("Satır aralığı"), "rowHeight", [(L("Sıkışık · 20 pt"), 20), (L("Normal · 24 pt"), 24), (L("Rahat · 30 pt"), 30)], view)
        popup(L("Tarih biçimi"), "dateStyle", [(L("Kısa tarih ve saat"), "short"), (L("Uzun tarih ve saat"), "long")], view)
        check(L("Klasörleri dosyalardan önce göster"), "foldersFirst", view)
        check(L("Uzantı sütununu göster"), "extensions", view)
        check(L("Görseller, PDF ve videolar için küçük resim üret"), "thumbnails", view)
        check(L("Gizli dosyaları göster"), "hiddenDefault", view)
        check(L("Komut satırını göster"), "commandBar", view)
        let files = page(L("Dosyalar"), L("Dosya kopyalama ve taşıma davranışları. Aynı adlı dosyalar otomatik olarak ezilmez."))
        popup(L("Ad çakışması"), "collision", [(L("Her seferinde sor"), "ask"), (L("İkisini de koru · (2), (3)…"), "keep"), (L("Hedefte varsa gelen dosyayı atla"), "skip")], files)
        check(L("Çöp Kutusu’na taşımadan önce sor"), "confirmTrash", files)
        check(L("Karşı panele taşımadan önce sor"), "confirmMove", files)
        let note = NSTextField(wrappingLabelWithString: L("Kopyalama ve taşıma işlemleri arka planda çalışır. İptal, devam eden tek dosya tamamlandıktan sonra uygulanır. Klasör eşitleme, değişen hedefleri .totalcommand-backup adıyla korur.")); note.widthAnchor.constraint(equalToConstant: 720).isActive = true; files.addArrangedSubview(note)
        let archive = page(L("Arşivler"), L("ZIP ve 7z oluşturma, sistem arşiv motoruyla çıkarma. Arşiv içinde gezinme geçici bir klasör kullanır; değişiklikler özgün arşive geri yazılmaz."))
        popup(L("Sıkıştır düğmesinin biçimi"), "archiveFormat", [(L("ZIP · yaygın uyumluluk"), "zip"), (L("7z · 7-Zip biçimi"), "7zip")], archive)
        check(L("Arşive çift tıklayınca panelde gezin"), "browseArchives", archive)
        let archiveNote = NSTextField(wrappingLabelWithString: L("Bu seçenek kapalıysa arşiv macOS’un varsayılan uygulamasıyla açılır. Arşiv menüsünden ZIP veya 7z biçimini ayrıca seçebilirsiniz. Şifreli arşivler bu sürümde desteklenmez.")); archiveNote.widthAnchor.constraint(equalToConstant: 720).isActive = true; archive.addArrangedSubview(archiveNote)
        let search = page(L("Arama"), L("Dosya Ara, etkin klasörün alt klasörlerinde dosya adlarını tarar. Paneldeki filtre yalnızca mevcut klasörü süzer."))
        check(L("Alt klasör aramasına gizli dosyaları dahil et"), "searchHidden", search)
        popup(L("En fazla sonuç"), "searchLimit", [(L("100 sonuç"), 100), (L("1.000 sonuç"), 1000), (L("5.000 sonuç"), 5000)], search)
        let keys = page(L("Klavye"), L("Fonksiyon tuşlarına atanacak işlemleri seçin. Mac klavyesinde F tuşları için Fn tuşunu kullanmanız gerekebilir."))
        check(L("F2–F8 kısayollarını etkinleştir"), "functionKeys", keys)
        check(L("Boşluk tuşuyla Quick Look önizleme"), "spacePreview", keys)
        let actions: [(String, Any)] = [(L("Önizle"), "preview"), (L("Düzenle"), "edit"), (L("Kopyala"), "copy"), (L("Taşı"), "move"), (L("Yeni klasör"), "folder"), (L("Çöpe taşı"), "trash"), (L("Yeniden adlandır"), "rename"), (L("Dosya ara"), "find")]
        for n in 3...8 { popup("F\(n)", "keyF\(n)", actions, keys) }
        let updates = page(L("Güncellemeler"), L("Yeni sürümleri GitHub üzerinden kontrol edin. İndirme sayfasını açarak kurulumu kendiniz başlatabilirsiniz."))
        popup(L("Otomatik kontrol"), "updateInterval", [(L("Yalnızca elle"), 0), (L("Günde bir"), 1), (L("Haftada bir"), 7)], updates)
        check(L("Önizleme sürümlerini de bildir"), "updatePreviews", updates)
        let privacy = NSTextField(wrappingLabelWithString: L("Kontrol sırasında GitHub’a uygulama sürümü ve standart bağlantı bilgileri iletilir. Dosyalarınız ve dosya yollarınız gönderilmez. Otomatik kontrol varsayılan olarak kapalıdır."))
        privacy.widthAnchor.constraint(equalToConstant: 720).isActive = true; privacy.textColor = .secondaryLabelColor; privacy.font = .systemFont(ofSize: 12); updates.addArrangedSubview(privacy)
        let updateButton = NSButton(title: L("Şimdi Kontrol Et"), target: self, action: #selector(checkUpdates)); updateButton.isEnabled = !checkingUpdates; self.updateButton = updateButton; updates.addArrangedSubview(updateButton)
        let status = NSTextField(wrappingLabelWithString: updateMessage); status.widthAnchor.constraint(equalToConstant: 720).isActive = true; status.font = .systemFont(ofSize: 12); updateStatus = status; updates.addArrangedSubview(status)
        tabs.selectTabViewItem(at: 0)
        let footer = NSStackView(); footer.spacing = 10
        let label = NSTextField(labelWithString: L("Total Command {0} · Değişiklikler otomatik kaydedilir", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1")); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
        footer.addArrangedSubview(label); footer.addArrangedSubview(NSView()); footer.addArrangedSubview(NSButton(title: L("Varsayılanlara Dön…"), target: self, action: #selector(reset)))
        footer.translatesAutoresizingMaskIntoConstraints = false
        let content = window!.contentView!; content.subviews.forEach { $0.removeFromSuperview() }; content.addSubview(tabs); content.addSubview(footer)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18), tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18), tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 18), tabs.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14), footer.leadingAnchor.constraint(equalTo: tabs.leadingAnchor), footer.trailingAnchor.constraint(equalTo: tabs.trailingAnchor), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
    }
    func row(_ label: String, _ control: NSView, _ stack: NSStackView) {
        let title = NSTextField(labelWithString: label); title.font = .systemFont(ofSize: 12); title.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let row = NSStackView(views: [title, control]); row.spacing = 12; stack.addArrangedSubview(row)
    }
    func check(_ label: String, _ key: String, _ stack: NSStackView) {
        let control = NSButton(checkboxWithTitle: label, target: self, action: #selector(change(_:))); control.identifier = NSUserInterfaceItemIdentifier(key); control.state = Prefs.bool(key) ? .on : .off; controls[key] = control; stack.addArrangedSubview(control)
    }
    func popup(_ label: String, _ key: String, _ values: [(String, Any)], _ stack: NSStackView) {
        let control = NSPopUpButton(); control.identifier = NSUserInterfaceItemIdentifier(key); control.target = self; control.action = #selector(change(_:)); control.widthAnchor.constraint(equalToConstant: 340).isActive = true
        for (title, value) in values { control.addItem(withTitle: title); control.lastItem?.representedObject = value; if String(describing: value) == String(describing: Prefs.store.object(forKey: key) ?? "") { control.select(control.lastItem) } }
        controls[key] = control; row(label, control, stack)
    }
    func path(_ label: String, _ key: String, _ stack: NSStackView) {
        let field = NSTextField(string: Prefs.string(key)); field.identifier = NSUserInterfaceItemIdentifier(key); field.delegate = self; field.widthAnchor.constraint(equalToConstant: 345).isActive = true; field.font = .systemFont(ofSize: 11); field.lineBreakMode = .byTruncatingMiddle; controls[key] = field
        let choose = NSButton(title: L("Seç…"), target: self, action: #selector(choose(_:))); choose.identifier = NSUserInterfaceItemIdentifier(key)
        let group = NSStackView(views: [field, choose]); group.spacing = 7; row(label, group, stack)
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let key = field.identifier?.rawValue else { return }
        let value = NSString(string: field.stringValue).expandingTildeInPath
        let url = URL(fileURLWithPath: value)
        let valid = key == "editor" ? FileManager.default.fileExists(atPath: value) && url.pathExtension == "app" : (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if valid { Prefs.set(key, value); changed?() } else { field.stringValue = Prefs.string(key); NSSound.beep() }
    }
    @objc func choose(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }; let panel = NSOpenPanel(); panel.canChooseDirectories = key != "editor"; panel.canChooseFiles = key == "editor"; panel.treatsFilePackagesAsDirectories = false
        if key == "editor" { panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle] }
        if panel.runModal() == .OK, let url = panel.url { Prefs.set(key, url.path); (controls[key] as? NSTextField)?.stringValue = url.path; changed?() }
    }
    @objc func change(_ sender: NSControl) {
        guard let key = sender.identifier?.rawValue else { return }
        if let popup = sender as? NSPopUpButton, let value = popup.selectedItem?.representedObject { Prefs.set(key, value) }
        else if let button = sender as? NSButton { Prefs.set(key, button.state == .on) }
        changed?()
    }
    @objc func checkUpdates() { checkForUpdates?() }
    @objc func reset() {
        let alert = NSAlert(); alert.messageText = L("Ayarlar varsayılana dönsün mü?"); alert.informativeText = L("Favoriler ve kayıtlı sekmeler korunur."); alert.addButton(withTitle: L("Varsayılana Dön")); alert.addButton(withTitle: L("Vazgeç"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }; for key in Prefs.defaults.keys { Prefs.store.removeObject(forKey: key) }; build(); changed?()
    }
}
