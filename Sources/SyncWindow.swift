// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa

final class SyncTableCellView: NSTableCellView {
    let label = NSTextField()

    init(identifier: String) {
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)

        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, alignment: NSTextAlignment = .left, color: NSColor = .labelColor, bold: Bool = false) {
        label.stringValue = text
        label.alignment = alignment
        label.textColor = color
        label.font = bold ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 11)
    }
}

final class SyncWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let leftDir: URL
    private let rightDir: URL
    var onStartSync: (([SyncItem]) -> Void)?

    private var allItems: [SyncItem] = []
    private var displayedItems: [SyncItem] = []

    private let subdirsCheck = NSButton(checkboxWithTitle: L("Alt klasörleri dahil et"), target: nil, action: nil)
    private let contentCheck = NSButton(checkboxWithTitle: L("İçeriğe göre (SHA-256)"), target: nil, action: nil)
    private let asymmetricCheck = NSButton(checkboxWithTitle: L("Tek yönlü (Asimetrik)"), target: nil, action: nil)

    private let filterRightBtn = NSButton(title: "->", target: nil, action: nil)
    private let filterEqualBtn = NSButton(title: "=", target: nil, action: nil)
    private let filterConflictBtn = NSButton(title: "≠", target: nil, action: nil)
    private let filterLeftBtn = NSButton(title: "<-", target: nil, action: nil)

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var diffController: DiffWindowController?

    init(leftDir: URL, rightDir: URL) {
        self.leftDir = leftDir
        self.rightDir = rightDir

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Klasörleri Eşitle (Synchronize Dirs)")
        win.minSize = NSSize(width: 860, height: 500)
        super.init(window: win)

        setupUI()
        startComparison()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // Top folder headers
        let leftLabel = NSTextField(labelWithString: "\(L("Sol:")) \(leftDir.path)")
        leftLabel.font = .systemFont(ofSize: 12, weight: .bold)
        leftLabel.lineBreakMode = .byTruncatingMiddle

        let rightLabel = NSTextField(labelWithString: "\(L("Sağ:")) \(rightDir.path)")
        rightLabel.font = .systemFont(ofSize: 12, weight: .bold)
        rightLabel.lineBreakMode = .byTruncatingMiddle

        let folderRow = NSStackView(views: [leftLabel, NSView(), rightLabel])
        folderRow.distribution = .fillEqually
        folderRow.spacing = 10

        // Options
        subdirsCheck.state = .on
        contentCheck.state = .off
        asymmetricCheck.state = .off

        for b in [filterRightBtn, filterEqualBtn, filterConflictBtn, filterLeftBtn] {
            b.setButtonType(.pushOnPushOff)
            b.state = .on
            b.bezelStyle = .texturedRounded
            b.target = self
            b.action = #selector(filterChanged)
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let compareBtn = NSButton(title: L("Karşılaştır"), target: self, action: #selector(startComparison))
        compareBtn.bezelStyle = .rounded

        let optionsH = NSStackView(views: [
            subdirsCheck, contentCheck, asymmetricCheck,
            NSView(),
            filterRightBtn, filterEqualBtn, filterConflictBtn, filterLeftBtn,
            compareBtn
        ])
        optionsH.spacing = 10
        optionsH.alignment = .centerY

        // Table Columns
        let cols = [
            ("lFile", L("Sol Dosya"), 270.0),
            ("lMeta", L("Boyut / Tarih"), 135.0),
            ("dir", L("Yön"), 55.0),
            ("rMeta", L("Boyut / Tarih"), 135.0),
            ("rFile", L("Sağ Dosya"), 270.0)
        ]

        for (id, title, width) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            tableView.addTableColumn(col)
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 4, height: 2)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Bottom Bar
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let syncBtn = NSButton(title: L("Senkronize Et"), target: self, action: #selector(syncClicked))
        syncBtn.keyEquivalent = "\r"
        let closeBtn = NSButton(title: L("Kapat"), target: self, action: #selector(closeClicked))

        let bottomRow = NSStackView(views: [statusLabel, NSView(), closeBtn, syncBtn])
        bottomRow.spacing = 10
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [folderRow, optionsH, scroll, bottomRow])
        rootV.orientation = .vertical
        rootV.spacing = 10
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            folderRow.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            optionsH.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    @objc func startComparison() {
        statusLabel.stringValue = L("Aranıyor")
        let opt = SyncOptions(
            subdirs: subdirsCheck.state == .on,
            byContent: contentCheck.state == .on,
            ignoreDate: false,
            asymmetric: asymmetricCheck.state == .on
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let items = try SyncEngine.compareDirectories(left: self.leftDir, right: self.rightDir, options: opt)
                DispatchQueue.main.async {
                    self.allItems = items
                    self.applyFilter()
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func filterChanged() {
        applyFilter()
    }

    private func applyFilter() {
        let showRight = filterRightBtn.state == .on
        let showEqual = filterEqualBtn.state == .on
        let showConflict = filterConflictBtn.state == .on
        let showLeft = filterLeftBtn.state == .on

        displayedItems = allItems.filter { item in
            switch item.direction {
            case .copyRight, .deleteRight: return showRight
            case .equal: return showEqual
            case .conflict: return showConflict
            case .copyLeft: return showLeft
            }
        }

        tableView.reloadData()

        let toRightCount = allItems.filter { $0.direction == .copyRight }.count
        let toLeftCount = allItems.filter { $0.direction == .copyLeft }.count
        let equalCount = allItems.filter { $0.direction == .equal }.count
        let conflictCount = allItems.filter { $0.direction == .conflict }.count

        statusLabel.stringValue = L("Sol → Sağ: {0} · Sağ → Sol: {1} · Eşit: {2} · Çakışma: {3}", toRightCount, toLeftCount, equalCount, conflictCount)
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.selectedRow
        guard displayedItems.indices.contains(row) else { return }
        let item = displayedItems[row]

        if let lURL = item.leftURL, let rURL = item.rightURL,
           FileManager.default.fileExists(atPath: lURL.path),
           FileManager.default.fileExists(atPath: rURL.path) {
            let diff = DiffWindowController(leftURL: lURL, rightURL: rURL)
            diffController = diff
            diff.showWindow(nil)
            diff.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func syncClicked() {
        let actionable = displayedItems.filter(\.isActionable)
        guard !actionable.isEmpty else {
            let a = NSAlert()
            a.messageText = L("Eşitle")
            a.informativeText = L("Eşitlenecek işlem bulunamadı.")
            a.runModal()
            return
        }

        window?.close()
        onStartSync?(actionable)
    }

    @objc private func closeClicked() {
        window?.close()
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue, displayedItems.indices.contains(row) else { return nil }
        let item = displayedItems[row]
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(colId), owner: self) as? SyncTableCellView) ?? SyncTableCellView(identifier: colId)

        switch colId {
        case "lFile":
            cell.configure(text: item.leftURL != nil ? item.relativePath : "", alignment: .left)

        case "lMeta":
            if let size = item.leftSize, let date = item.leftDate {
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
                cell.configure(text: "\(sizeStr) · \(dateStr)", alignment: .right, color: .secondaryLabelColor)
            } else {
                cell.configure(text: "")
            }

        case "dir":
            let color: NSColor
            switch item.direction {
            case .copyRight, .deleteRight: color = .systemGreen
            case .copyLeft: color = .systemBlue
            case .equal: color = .secondaryLabelColor
            case .conflict: color = .systemRed
            }
            cell.configure(text: item.direction.rawValue, alignment: .center, color: color, bold: true)

        case "rMeta":
            if let size = item.rightSize, let date = item.rightDate {
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
                cell.configure(text: "\(sizeStr) · \(dateStr)", alignment: .left, color: .secondaryLabelColor)
            } else {
                cell.configure(text: "")
            }

        case "rFile":
            cell.configure(text: item.rightURL != nil ? item.relativePath : "", alignment: .left)

        default:
            break
        }

        return cell
    }
}
