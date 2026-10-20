// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa

final class DiffTableCellView: NSTableCellView {
    let label = NSTextField()

    init(identifier: String, monospaced: Bool = false) {
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)

        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byClipping
        label.font = monospaced ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, alignment: NSTextAlignment = .left, color: NSColor = .labelColor, backgroundColor: NSColor? = nil) {
        label.stringValue = text
        label.alignment = alignment
        label.textColor = color
        wantsLayer = true
        layer?.backgroundColor = backgroundColor?.cgColor ?? NSColor.clear.cgColor
    }
}

final class DiffWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let leftURL: URL
    private let rightURL: URL

    private var diffResult: DiffResult?
    private var rows: [AlignedDiffRow] = []
    private var diffRowIndices: [Int] = []
    private var currentDiffPointer = -1

    private let statusLabel = NSTextField(labelWithString: "")
    private let counterLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let binaryView = NSView()
    private let scroll = NSScrollView()

    init(leftURL: URL, rightURL: URL) {
        self.leftURL = leftURL
        self.rightURL = rightURL

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Dosya İçeriği Karşılaştırma")
        win.minSize = NSSize(width: 800, height: 480)
        super.init(window: win)

        setupUI()
        reloadComparison()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        // Top paths
        let leftLabel = NSTextField(labelWithString: "\(L("Sol:")) \(leftURL.lastPathComponent)")
        leftLabel.font = .systemFont(ofSize: 12, weight: .bold)
        leftLabel.toolTip = leftURL.path

        let rightLabel = NSTextField(labelWithString: "\(L("Sağ:")) \(rightURL.lastPathComponent)")
        rightLabel.font = .systemFont(ofSize: 12, weight: .bold)
        rightLabel.toolTip = rightURL.path

        let prevBtn = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: L("Önceki Fark"))!, target: self, action: #selector(prevDiff))
        prevBtn.bezelStyle = .texturedRounded
        prevBtn.toolTip = L("Önceki Fark")

        let nextBtn = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: L("Sonraki Fark"))!, target: self, action: #selector(nextDiff))
        nextBtn.bezelStyle = .texturedRounded
        nextBtn.toolTip = L("Sonraki Fark")

        let refreshBtn = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: L("Yeniden Karşılaştır"))!, target: self, action: #selector(refreshClicked))
        refreshBtn.bezelStyle = .texturedRounded
        refreshBtn.toolTip = L("Yeniden Karşılaştır")

        counterLabel.font = .systemFont(ofSize: 12, weight: .medium)
        counterLabel.textColor = .secondaryLabelColor

        let topRow = NSStackView(views: [leftLabel, NSView(), prevBtn, nextBtn, counterLabel, refreshBtn, NSView(), rightLabel])
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        // Table View columns
        let cols = [
            ("lNum", L("Satır"), 45.0, false),
            ("lContent", "\(leftURL.lastPathComponent)", 440.0, true),
            ("rNum", L("Satır"), 45.0, false),
            ("rContent", "\(rightURL.lastPathComponent)", 440.0, true)
        ]

        for (id, title, width, resizable) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.resizingMask = resizable ? .userResizingMask : []
            tableView.addTableColumn(col)
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 4, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Status bar
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let rootV = NSStackView(views: [topRow, scroll, statusLabel])
        rootV.orientation = .vertical
        rootV.spacing = 8
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            topRow.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    func reloadComparison() {
        do {
            let result = try DiffEngine.compare(leftURL: leftURL, rightURL: rightURL)
            self.diffResult = result

            switch result {
            case .binary(let bin):
                rows = []
                diffRowIndices = []
                currentDiffPointer = -1
                scroll.isHidden = true
                showBinaryResult(bin)

            case .text(let alignedRows, let diffCount, let added, let deleted, let modified):
                scroll.isHidden = false
                binaryView.removeFromSuperview()
                rows = alignedRows
                diffRowIndices = alignedRows.compactMap { $0.isDifference ? $0.index : nil }
                currentDiffPointer = diffRowIndices.isEmpty ? -1 : 0

                tableView.reloadData()
                updateTextStatus(diffCount: diffCount, added: added, deleted: deleted, modified: modified)
                if currentDiffPointer >= 0 {
                    jumpToDiff(index: 0)
                }
            }
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func showBinaryResult(_ bin: BinaryDiffResult) {
        guard let content = window?.contentView else { return }
        binaryView.removeFromSuperview()
        binaryView.subviews.forEach { $0.removeFromSuperview() }
        binaryView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(binaryView)

        let iconName = bin.isIdentical ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        let iconColor = bin.isIdentical ? NSColor.systemGreen : NSColor.systemOrange
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: "")!)
        icon.contentTintColor = iconColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titleText = bin.isIdentical ? L("Dosyalar birebir aynı.") : L("İkili (Binary) dosyalar farklı.")
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)

        let leftSizeStr = ByteCountFormatter.string(fromByteCount: bin.leftSize, countStyle: .file)
        let rightSizeStr = ByteCountFormatter.string(fromByteCount: bin.rightSize, countStyle: .file)

        var details = "\(L("Sol:")) \(leftSizeStr) · SHA-256: \(bin.leftSHA256)\n\(L("Sağ:")) \(rightSizeStr) · SHA-256: \(bin.rightSHA256)"
        if let offset = bin.firstDifferenceOffset {
            let hexOffset = String(format: "0x%08X (%d. bayt)", offset, offset)
            details += "\n\(L("İlk fark offseti: {0}", hexOffset))"
        }

        let detailLabel = NSTextField(wrappingLabelWithString: details)
        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.alignment = .center

        let card = NSStackView(views: [icon, titleLabel, detailLabel])
        card.orientation = .vertical
        card.spacing = 10
        card.alignment = .centerX
        card.translatesAutoresizingMaskIntoConstraints = false
        binaryView.addSubview(card)

        NSLayoutConstraint.activate([
            binaryView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            binaryView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            binaryView.topAnchor.constraint(equalTo: content.topAnchor, constant: 50),
            binaryView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -30),
            card.centerXAnchor.constraint(equalTo: binaryView.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: binaryView.centerYAnchor)
        ])

        statusLabel.stringValue = titleText
        counterLabel.stringValue = bin.isIdentical ? L("Fark yok") : "1"
    }

    private func updateTextStatus(diffCount: Int, added: Int, deleted: Int, modified: Int) {
        if diffCount == 0 {
            statusLabel.stringValue = L("Dosyalar birebir aynı.")
            counterLabel.stringValue = L("Fark yok")
        } else {
            statusLabel.stringValue = L("{0} farklılık · {1} eklenen · {2} silinen · {3} değişen", diffCount, added, deleted, modified)
            let curr = currentDiffPointer >= 0 ? currentDiffPointer + 1 : 0
            counterLabel.stringValue = L("Fark: {0} / {1}", curr, diffRowIndices.count)
        }
    }

    private func jumpToDiff(index: Int) {
        guard diffRowIndices.indices.contains(index) else { return }
        currentDiffPointer = index
        let rowIndex = diffRowIndices[index]
        tableView.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(rowIndex)
        counterLabel.stringValue = L("Fark: {0} / {1}", currentDiffPointer + 1, diffRowIndices.count)
    }

    @objc private func nextDiff() {
        guard !diffRowIndices.isEmpty else { return }
        let nextIdx = (currentDiffPointer + 1) % diffRowIndices.count
        jumpToDiff(index: nextIdx)
    }

    @objc private func prevDiff() {
        guard !diffRowIndices.isEmpty else { return }
        let prevIdx = currentDiffPointer <= 0 ? diffRowIndices.count - 1 : currentDiffPointer - 1
        jumpToDiff(index: prevIdx)
    }

    @objc private func refreshClicked() {
        reloadComparison()
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue, rows.indices.contains(row) else { return nil }
        let r = rows[row]
        let view = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(colId), owner: self) as? DiffTableCellView) ?? DiffTableCellView(identifier: colId, monospaced: colId.hasSuffix("Content"))

        let delColor = NSColor.systemRed.withAlphaComponent(0.18)
        let addColor = NSColor.systemGreen.withAlphaComponent(0.18)
        let modColor = NSColor.systemOrange.withAlphaComponent(0.18)

        switch colId {
        case "lNum":
            let text = r.leftLineNum.map(String.init) ?? ""
            let bg: NSColor? = r.leftType == .deleted ? delColor : (r.leftType == .modified ? modColor : nil)
            view.configure(text: text, alignment: .right, color: .secondaryLabelColor, backgroundColor: bg)

        case "lContent":
            let text = r.leftContent ?? ""
            let bg: NSColor? = r.leftType == .deleted ? delColor : (r.leftType == .modified ? modColor : nil)
            view.configure(text: text, alignment: .left, color: .labelColor, backgroundColor: bg)

        case "rNum":
            let text = r.rightLineNum.map(String.init) ?? ""
            let bg: NSColor? = r.rightType == .added ? addColor : (r.rightType == .modified ? modColor : nil)
            view.configure(text: text, alignment: .right, color: .secondaryLabelColor, backgroundColor: bg)

        case "rContent":
            let text = r.rightContent ?? ""
            let bg: NSColor? = r.rightType == .added ? addColor : (r.rightType == .modified ? modColor : nil)
            view.configure(text: text, alignment: .left, color: .labelColor, backgroundColor: bg)

        default:
            break
        }

        return view
    }
}
