// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa
import UniformTypeIdentifiers

enum Prefs {
    static var store = UserDefaults.standard
    static let defaults: [String: Any] = [
        "updateInterval": 0, "updatePreviews": false,
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
        window.title = "Total Command — Ayarlar"; window.isReleasedWhenClosed = false
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
        let general = page("Genel", "Ayarlar otomatik kaydedilir. Başlangıç klasörleri bir sonraki açılışta kullanılır; sekmeleri geri yükleme açıksa son sekmeler önceliklidir.")
        check("Son açık sekmeleri geri yükle", "restoreTabs", general)
        path("Sol başlangıç klasörü", "leftStart", general)
        path("Sağ başlangıç klasörü", "rightStart", general)
        path("Metin düzenleyici", "editor", general)
        popup("Varsayılan görünüm", "defaultView", [("Ayrıntılı liste", 0), ("Büyük simgeler", 1)], general)
        let view = page("Görünüm", "Değişiklikler iki panele anında uygulanır. Liste sütunlarına tıklayarak sıralamayı değiştirebilirsiniz.")
        popup("Tema", "theme", [("macOS ile aynı", "system"), ("Açık", "light"), ("Koyu", "dark")], view)
        popup("Yazı boyutu", "fontSize", [("11 punto", 11), ("12 punto", 12), ("13 punto", 13), ("14 punto", 14), ("15 punto", 15)], view)
        popup("Satır aralığı", "rowHeight", [("Sıkışık · 20 pt", 20), ("Normal · 24 pt", 24), ("Rahat · 30 pt", 30)], view)
        popup("Tarih biçimi", "dateStyle", [("Kısa tarih ve saat", "short"), ("Uzun tarih ve saat", "long")], view)
        check("Klasörleri dosyalardan önce göster", "foldersFirst", view)
        check("Uzantı sütununu göster", "extensions", view)
        check("Görseller, PDF ve videolar için küçük resim üret", "thumbnails", view)
        check("Gizli dosyaları göster", "hiddenDefault", view)
        check("Komut satırını göster", "commandBar", view)
        let files = page("Dosyalar", "Dosya kopyalama ve taşıma davranışları. Aynı adlı dosyalar otomatik olarak ezilmez.")
        popup("Ad çakışması", "collision", [("Her seferinde sor", "ask"), ("İkisini de koru · (2), (3)…", "keep"), ("Hedefte varsa gelen dosyayı atla", "skip")], files)
        check("Çöp Kutusu’na taşımadan önce sor", "confirmTrash", files)
        check("Karşı panele taşımadan önce sor", "confirmMove", files)
        let note = NSTextField(wrappingLabelWithString: "Kopyalama ve taşıma işlemleri arka planda çalışır. İptal, devam eden tek dosya tamamlandıktan sonra uygulanır. Klasör eşitleme, değişen hedefleri .totalcommand-backup adıyla korur."); note.widthAnchor.constraint(equalToConstant: 720).isActive = true; files.addArrangedSubview(note)
        let archive = page("Arşivler", "ZIP ve 7z oluşturma, sistem arşiv motoruyla çıkarma. Arşiv içinde gezinme geçici bir klasör kullanır; değişiklikler özgün arşive geri yazılmaz.")
        popup("Sıkıştır düğmesinin biçimi", "archiveFormat", [("ZIP · yaygın uyumluluk", "zip"), ("7z · 7-Zip biçimi", "7zip")], archive)
        check("Arşive çift tıklayınca panelde gezin", "browseArchives", archive)
        let archiveNote = NSTextField(wrappingLabelWithString: "Bu seçenek kapalıysa arşiv macOS’un varsayılan uygulamasıyla açılır. Arşiv menüsünden ZIP veya 7z biçimini ayrıca seçebilirsiniz. Şifreli arşivler bu sürümde desteklenmez."); archiveNote.widthAnchor.constraint(equalToConstant: 720).isActive = true; archive.addArrangedSubview(archiveNote)
        let search = page("Arama", "Dosya Ara, etkin klasörün alt klasörlerinde dosya adlarını tarar. Paneldeki filtre yalnızca mevcut klasörü süzer.")
        check("Alt klasör aramasına gizli dosyaları dahil et", "searchHidden", search)
        popup("En fazla sonuç", "searchLimit", [("100 sonuç", 100), ("1.000 sonuç", 1000), ("5.000 sonuç", 5000)], search)
        let keys = page("Klavye", "Fonksiyon tuşlarına atanacak işlemleri seçin. Mac klavyesinde F tuşları için Fn tuşunu kullanmanız gerekebilir.")
        check("F2–F8 kısayollarını etkinleştir", "functionKeys", keys)
        check("Boşluk tuşuyla Quick Look önizleme", "spacePreview", keys)
        let actions: [(String, Any)] = [("Önizle", "preview"), ("Düzenle", "edit"), ("Kopyala", "copy"), ("Taşı", "move"), ("Yeni klasör", "folder"), ("Çöpe taşı", "trash"), ("Yeniden adlandır", "rename"), ("Dosya ara", "find")]
        for n in 3...8 { popup("F\(n)", "keyF\(n)", actions, keys) }
        let updates = page("Güncellemeler", "Yeni sürümleri GitHub üzerinden kontrol edin. İndirme sayfasını açarak kurulumu kendiniz başlatabilirsiniz.")
        popup("Otomatik kontrol", "updateInterval", [("Yalnızca elle", 0), ("Günde bir", 1), ("Haftada bir", 7)], updates)
        check("Önizleme sürümlerini de bildir", "updatePreviews", updates)
        let privacy = NSTextField(wrappingLabelWithString: "Kontrol sırasında GitHub’a uygulama sürümü ve standart bağlantı bilgileri iletilir. Dosyalarınız ve dosya yollarınız gönderilmez. Otomatik kontrol varsayılan olarak kapalıdır.")
        privacy.widthAnchor.constraint(equalToConstant: 720).isActive = true; privacy.textColor = .secondaryLabelColor; privacy.font = .systemFont(ofSize: 12); updates.addArrangedSubview(privacy)
        let updateButton = NSButton(title: "Şimdi Kontrol Et", target: self, action: #selector(checkUpdates)); updateButton.isEnabled = !checkingUpdates; self.updateButton = updateButton; updates.addArrangedSubview(updateButton)
        let status = NSTextField(wrappingLabelWithString: updateMessage); status.widthAnchor.constraint(equalToConstant: 720).isActive = true; status.font = .systemFont(ofSize: 12); updateStatus = status; updates.addArrangedSubview(status)
        tabs.selectTabViewItem(at: 0)
        let footer = NSStackView(); footer.spacing = 10
        let label = NSTextField(labelWithString: "Total Command \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1") · Değişiklikler otomatik kaydedilir"); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
        footer.addArrangedSubview(label); footer.addArrangedSubview(NSView()); footer.addArrangedSubview(NSButton(title: "Varsayılanlara Dön…", target: self, action: #selector(reset)))
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
        for (title, value) in values { control.addItem(withTitle: title); control.lastItem?.representedObject = value; if String(describing: value) == String(describing: UserDefaults.standard.object(forKey: key)!) { control.select(control.lastItem) } }
        controls[key] = control; row(label, control, stack)
    }
    func path(_ label: String, _ key: String, _ stack: NSStackView) {
        let field = NSTextField(string: Prefs.string(key)); field.identifier = NSUserInterfaceItemIdentifier(key); field.delegate = self; field.widthAnchor.constraint(equalToConstant: 345).isActive = true; field.font = .systemFont(ofSize: 11); field.lineBreakMode = .byTruncatingMiddle; controls[key] = field
        let choose = NSButton(title: "Seç…", target: self, action: #selector(choose(_:))); choose.identifier = NSUserInterfaceItemIdentifier(key)
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
        let alert = NSAlert(); alert.messageText = "Ayarlar varsayılana dönsün mü?"; alert.informativeText = "Favoriler ve kayıtlı sekmeler korunur."; alert.addButton(withTitle: "Varsayılana Dön"); alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }; for key in Prefs.defaults.keys { UserDefaults.standard.removeObject(forKey: key) }; build(); changed?()
    }
}
