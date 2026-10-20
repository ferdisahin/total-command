// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa

final class SiteStore {
    static let shared = SiteStore()
    private let key = "savedRemoteSites"

    func loadSites() -> [RemoteSite] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let sites = try? JSONDecoder().decode([RemoteSite].self, from: data) else {
            return [
                RemoteSite(name: "Örnek SFTP Sunucusu", protocolType: .sftp, host: "sftp.example.com", port: 22, username: "user", password: "", privateKeyPath: "~/.ssh/id_ed25519", remotePath: "/"),
                RemoteSite(name: "Örnek Web FTP", protocolType: .ftp, host: "ftp.example.com", port: 21, username: "ftpuser", password: "", privateKeyPath: "", remotePath: "/public_html")
            ]
        }
        return sites
    }

    func saveSites(_ sites: [RemoteSite]) {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

final class SiteManagerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var sites: [RemoteSite] = []
    var onConnect: ((RemoteSite) -> Void)?

    private let table = NSTableView()
    private let nameField = NSTextField()
    private let protoPopup = NSPopUpButton()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    private let userField = NSTextField()
    private let passField = NSSecureTextField()
    private let keyField = NSTextField()
    private let pathField = NSTextField()

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = L("FTP / SFTP Bağlantı Yöneticisi")
        win.minSize = NSSize(width: 600, height: 380)
        self.init(window: win)
        setupUI()
        sites = SiteStore.shared.loadSites()
        table.reloadData()
        if !sites.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            loadSiteDetails(sites[0])
        }
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // Table on left
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("site"))
        col.title = L("Kayıtlı Sunucular")
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(connectClicked)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Form on right
        for p in RemoteProtocol.allCases {
            protoPopup.addItem(withTitle: p.rawValue)
        }
        protoPopup.target = self
        protoPopup.action = #selector(protoChanged)

        let browseKeyBtn = NSButton(title: "…", target: self, action: #selector(browseKey))
        browseKeyBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let keyRow = NSStackView(views: [keyField, browseKeyBtn])
        keyRow.spacing = 4

        let formGrid = NSGridView(views: [
            [label(L("Bağlantı Adı:")), nameField],
            [label(L("Protokol:")), protoPopup],
            [label(L("Sunucu (Host):")), hostField],
            [label(L("Port:")), portField],
            [label(L("Kullanıcı Adı:")), userField],
            [label(L("Şifre:")), passField],
            [label(L("SSH Anahtarı:")), keyRow],
            [label(L("Uzak Dizin:")), pathField]
        ])
        formGrid.columnSpacing = 10
        formGrid.rowSpacing = 8
        formGrid.translatesAutoresizingMaskIntoConstraints = false

        // Buttons
        let newBtn = NSButton(title: L("Yeni"), target: self, action: #selector(newSiteClicked))
        let saveBtn = NSButton(title: L("Kaydet"), target: self, action: #selector(saveSiteClicked))
        let delBtn = NSButton(title: L("Sil"), target: self, action: #selector(deleteSiteClicked))
        let connectBtn = NSButton(title: L("Bağlan"), target: self, action: #selector(connectClicked))
        connectBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: L("Kapat"), target: self, action: #selector(cancelClicked))

        let btnRow = NSStackView(views: [newBtn, delBtn, saveBtn, NSView(), cancelBtn, connectBtn])
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let mainH = NSStackView(views: [scroll, formGrid])
        mainH.spacing = 14
        mainH.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [mainH, btnRow])
        rootV.orientation = .vertical
        rootV.spacing = 14
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            mainH.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            btnRow.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return l
    }

    private func loadSiteDetails(_ site: RemoteSite) {
        nameField.stringValue = site.name
        protoPopup.selectItem(withTitle: site.protocolType.rawValue)
        hostField.stringValue = site.host
        portField.stringValue = "\(site.port)"
        userField.stringValue = site.username
        passField.stringValue = site.password
        keyField.stringValue = site.privateKeyPath
        pathField.stringValue = site.remotePath
    }

    @objc private func protoChanged() {
        guard let title = protoPopup.selectedItem?.title,
              let p = RemoteProtocol(rawValue: title) else { return }
        if portField.stringValue.isEmpty || portField.stringValue == "21" || portField.stringValue == "22" {
            portField.stringValue = "\(p.defaultPort)"
        }
    }

    @objc private func browseKey() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = URL(fileURLWithPath: NSString(string: "~/.ssh").expandingTildeInPath)
        if openPanel.runModal() == .OK, let url = openPanel.url {
            keyField.stringValue = url.path
        }
    }

    @objc private func newSiteClicked() {
        let newSite = RemoteSite(name: L("Yeni Sunucu"), protocolType: .sftp, host: "", port: 22, username: "", password: "", privateKeyPath: "", remotePath: "/")
        sites.append(newSite)
        table.reloadData()
        let idx = sites.count - 1
        table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
        loadSiteDetails(newSite)
        nameField.becomeFirstResponder()
    }

    @objc private func deleteSiteClicked() {
        let row = table.selectedRow
        guard row >= 0, row < sites.count else { return }
        sites.remove(at: row)
        SiteStore.shared.saveSites(sites)
        table.reloadData()
        if !sites.isEmpty {
            let nextRow = min(row, sites.count - 1)
            table.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            loadSiteDetails(sites[nextRow])
        } else {
            newSiteClicked()
        }
    }

    @objc private func saveSiteClicked() {
        let row = table.selectedRow
        guard row >= 0, row < sites.count else { return }
        let proto = RemoteProtocol(rawValue: protoPopup.selectedItem?.title ?? "SFTP") ?? .sftp
        let port = Int(portField.stringValue) ?? proto.defaultPort

        sites[row].name = nameField.stringValue.isEmpty ? hostField.stringValue : nameField.stringValue
        sites[row].protocolType = proto
        sites[row].host = hostField.stringValue
        sites[row].port = port
        sites[row].username = userField.stringValue
        sites[row].password = passField.stringValue
        sites[row].privateKeyPath = keyField.stringValue
        sites[row].remotePath = pathField.stringValue.isEmpty ? "/" : pathField.stringValue

        SiteStore.shared.saveSites(sites)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    @objc private func connectClicked() {
        let row = table.selectedRow
        guard row >= 0, row < sites.count else { return }
        saveSiteClicked()
        let site = sites[row]
        window?.close()
        onConnect?(site)
    }

    @objc private func cancelClicked() {
        window?.close()
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        sites.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let site = sites[row]
        let cell = NSTextField(labelWithString: "\(site.name) (\(site.protocolType.rawValue))")
        cell.font = .systemFont(ofSize: 12)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row < sites.count else { return }
        loadSiteDetails(sites[row])
    }
}

final class QuickConnectController: NSWindowController {
    var onConnect: ((RemoteSite) -> Void)?

    private let protoPopup = NSPopUpButton()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    private let userField = NSTextField()
    private let passField = NSSecureTextField()
    private let pathField = NSTextField()

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = L("Hızlı Bağlan (Quick Connect)")
        self.init(window: win)
        setupUI()
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        for p in RemoteProtocol.allCases {
            protoPopup.addItem(withTitle: p.rawValue)
        }
        portField.stringValue = "22"
        pathField.stringValue = "/"

        protoPopup.target = self
        protoPopup.action = #selector(protoChanged)

        let form = NSGridView(views: [
            [label(L("Protokol:")), protoPopup],
            [label(L("Sunucu (Host):")), hostField],
            [label(L("Port:")), portField],
            [label(L("Kullanıcı Adı:")), userField],
            [label(L("Şifre:")), passField],
            [label(L("Uzak Dizin:")), pathField]
        ])
        form.columnSpacing = 10
        form.rowSpacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false

        let connectBtn = NSButton(title: L("Bağlan"), target: self, action: #selector(connectClicked))
        connectBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: L("İptal"), target: self, action: #selector(cancelClicked))
        let btnRow = NSStackView(views: [NSView(), cancelBtn, connectBtn])
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView(views: [form, btnRow])
        root.orientation = .vertical
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            form.widthAnchor.constraint(equalTo: root.widthAnchor),
            btnRow.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return l
    }

    @objc private func protoChanged() {
        guard let title = protoPopup.selectedItem?.title,
              let p = RemoteProtocol(rawValue: title) else { return }
        portField.stringValue = "\(p.defaultPort)"
    }

    @objc private func connectClicked() {
        guard !hostField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let proto = RemoteProtocol(rawValue: protoPopup.selectedItem?.title ?? "SFTP") ?? .sftp
        let port = Int(portField.stringValue) ?? proto.defaultPort
        let site = RemoteSite(name: hostField.stringValue,
                              protocolType: proto,
                              host: hostField.stringValue,
                              port: port,
                              username: userField.stringValue,
                              password: passField.stringValue,
                              privateKeyPath: "",
                              remotePath: pathField.stringValue.isEmpty ? "/" : pathField.stringValue)
        window?.close()
        onConnect?(site)
    }

    @objc private func cancelClicked() {
        window?.close()
    }
}
