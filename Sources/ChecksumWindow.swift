// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa

final class ChecksumCreateDialog: NSWindowController {
    private let files: [URL]
    private let baseDir: URL
    var onStartCreate: ((ChecksumAlgorithm, String, Bool) -> Void)?

    private let algoPopup = NSPopUpButton()
    private let filenameField = NSTextField()
    private let separateCheck = NSButton(checkboxWithTitle: L("Her dosya için ayrı sağlama dosyası oluştur"), target: nil, action: nil)

    init(files: [URL], baseDir: URL) {
        self.files = files
        self.baseDir = baseDir

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Sağlama Toplamı Oluştur (Checksum)")
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        for algo in ChecksumAlgorithm.allCases {
            algoPopup.addItem(withTitle: algo.rawValue)
        }
        algoPopup.selectItem(withTitle: ChecksumAlgorithm.sha256.rawValue)
        algoPopup.target = self
        algoPopup.action = #selector(algoChanged)

        updateDefaultFilename()

        separateCheck.target = self
        separateCheck.action = #selector(separateChanged)

        let grid = NSGridView(views: [
            [label(L("Seçili Dosyalar:")), valueLabel(L("{0} dosya seçildi", files.count))],
            [label(L("Algoritma:")), algoPopup],
            [label(L("Çıktı Dosyası:")), filenameField]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let createBtn = NSButton(title: L("Oluştur"), target: self, action: #selector(createClicked))
        createBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: L("İptal"), target: self, action: #selector(cancelClicked))

        let btnRow = NSStackView(views: [NSView(), cancelBtn, createBtn])
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [grid, separateCheck, btnRow])
        rootV.orientation = .vertical
        rootV.spacing = 14
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            grid.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            btnRow.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return l
    }

    private func valueLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        return l
    }

    private var currentAlgorithm: ChecksumAlgorithm {
        let title = algoPopup.selectedItem?.title ?? ChecksumAlgorithm.sha256.rawValue
        return ChecksumAlgorithm(rawValue: title) ?? .sha256
    }

    private func updateDefaultFilename() {
        let ext = currentAlgorithm.fileExtension
        let baseName: String
        if files.count == 1 {
            baseName = files[0].lastPathComponent
        } else {
            baseName = baseDir.lastPathComponent.isEmpty ? "checksums" : baseDir.lastPathComponent
        }
        filenameField.stringValue = "\(baseName).\(ext)"
    }

    @objc private func algoChanged() {
        updateDefaultFilename()
    }

    @objc private func separateChanged() {
        filenameField.isEnabled = separateCheck.state != .on
    }

    @objc private func createClicked() {
        let algo = currentAlgorithm
        let outName = filenameField.stringValue.trimmingCharacters(in: .whitespaces)
        let isSeparate = separateCheck.state == .on
        guard isSeparate || !outName.isEmpty else { return }
        window?.close()
        onStartCreate?(algo, outName, isSeparate)
    }

    @objc private func cancelClicked() {
        window?.close()
    }
}

final class ChecksumTableCellView: NSTableCellView {
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
        label.font = bold ? .boldSystemFont(ofSize: 11) : .systemFont(ofSize: 11)
    }
}

final class ChecksumVerifyWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let checksumFileURL: URL
    private let baseDir: URL
    private var records: [ChecksumRecord] = []
    private var algorithm: ChecksumAlgorithm = .sha256
    private let control = JobState()

    private let tableView = NSTableView()
    private let progressBar = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    init(checksumFileURL: URL) {
        self.checksumFileURL = checksumFileURL
        self.baseDir = checksumFileURL.deletingLastPathComponent()

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "\(L("Sağlama Toplamını Doğrula:")) \(checksumFileURL.lastPathComponent)"
        win.minSize = NSSize(width: 680, height: 380)
        super.init(window: win)
        setupUI()
        startVerification()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        let headerLabel = NSTextField(labelWithString: "\(L("Dosya:")) \(checksumFileURL.path)")
        headerLabel.font = .systemFont(ofSize: 11)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.lineBreakMode = .byTruncatingMiddle

        // Table setup
        let cols = [
            ("file", L("Dosya"), 280.0),
            ("status", L("Durum"), 130.0),
            ("expected", L("Beklenen Özet"), 200.0),
            ("actual", L("Hesaplanan Özet"), 200.0)
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
        tableView.intercellSpacing = NSSize(width: 6, height: 2)
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.style = .bar

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let closeBtn = NSButton(title: L("Kapat"), target: self, action: #selector(closeClicked))

        let bottomRow = NSStackView(views: [statusLabel, NSView(), closeBtn])
        bottomRow.spacing = 10
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [headerLabel, progressBar, scroll, bottomRow])
        rootV.orientation = .vertical
        rootV.spacing = 10
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            headerLabel.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            progressBar.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    private func startVerification() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let parsed = try ChecksumEngine.parseChecksumFile(url: self.checksumFileURL)
                self.algorithm = parsed.algorithm
                self.records = parsed.records

                DispatchQueue.main.async {
                    self.progressBar.maxValue = Double(max(1, self.records.count))
                    self.tableView.reloadData()
                    self.statusLabel.stringValue = L("Hesaplanıyor… ({0})", self.algorithm.rawValue)
                }

                _ = try ChecksumEngine.verifyRecords(records: parsed.records, baseDir: self.baseDir, algorithm: parsed.algorithm, control: self.control) { done, total, updatedRec in
                    DispatchQueue.main.async {
                        if done - 1 < self.records.count {
                            self.records[done - 1] = updatedRec
                        }
                        self.progressBar.doubleValue = Double(done)
                        self.tableView.reloadData()
                        self.updateStatusSummary()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func updateStatusSummary() {
        let total = records.count
        let okCount = records.filter { $0.status == .ok }.count
        let mismatchCount = records.filter {
            if case .mismatch = $0.status { return true }
            return false
        }.count
        let missingCount = records.filter { $0.status == .missing }.count

        statusLabel.stringValue = L("{0} dosya kontrol edildi: {1} geçerli, {2} hatalı, {3} eksik", total, okCount, mismatchCount, missingCount)
    }

    @objc private func closeClicked() {
        control.cancel()
        window?.close()
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        records.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue, records.indices.contains(row) else { return nil }
        let rec = records[row]
        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(colId), owner: self) as? ChecksumTableCellView) ?? ChecksumTableCellView(identifier: colId)

        switch colId {
        case "file":
            cell.configure(text: rec.relativePath, alignment: .left)

        case "status":
            let color: NSColor
            let title: String
            switch rec.status {
            case .ok:
                color = .systemGreen
                title = "✓ " + L("Geçti (OK)")
            case .mismatch:
                color = .systemRed
                title = "✗ " + L("Hatalı (Uyuşmuyor)")
            case .missing:
                color = .systemOrange
                title = "⚠ " + L("Eksik (Bulunamadı)")
            case .error(let msg):
                color = .systemRed
                title = "\(L("Hata")): \(msg)"
            }
            cell.configure(text: title, alignment: .left, color: color, bold: true)

        case "expected":
            cell.configure(text: rec.expectedHash, alignment: .left, color: .secondaryLabelColor)

        case "actual":
            let actual = rec.actualHash ?? "—"
            let isMismatch: Bool
            if case .mismatch = rec.status { isMismatch = true } else { isMismatch = false }
            cell.configure(text: actual, alignment: .left, color: isMismatch ? .systemRed : .secondaryLabelColor)

        default:
            break
        }

        return cell
    }
}
