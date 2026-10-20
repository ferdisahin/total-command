// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa

enum RenameCaseConversion: Int, CaseIterable {
    case none = 0
    case uppercase = 1
    case lowercase = 2
    case firstCapital = 3
    case titleCase = 4

    var title: String {
        switch self {
        case .none: return L("Değiştirme")
        case .uppercase: return L("TÜMÜ BÜYÜK")
        case .lowercase: return L("tümü küçük")
        case .firstCapital: return L("İlk harf büyük")
        case .titleCase: return L("Her Kelimenin Başı Büyük")
        }
    }
}

struct MultiRenameOptions {
    var namePattern: String = "[N]"
    var extPattern: String = "[E]"
    var search: String = ""
    var replace: String = ""
    var useRegex: Bool = false
    var caseSensitive: Bool = false
    var caseConversion: RenameCaseConversion = .none
    var counterStart: Int = 1
    var counterStep: Int = 1
    var counterDigits: Int = 1
}

struct MultiRenameItem: Equatable {
    let sourceURL: URL
    let oldName: String
    var newName: String
    var error: String?

    var willChange: Bool {
        oldName != newName && error == nil
    }
}

final class MultiRenameEngine {
    static func generateNames(urls: [URL], options: MultiRenameOptions) -> [MultiRenameItem] {
        let date = Date()
        let cal = Calendar.current
        let year = String(format: "%04d", cal.component(.year, from: date))
        let month = String(format: "%02d", cal.component(.month, from: date))
        let day = String(format: "%02d", cal.component(.day, from: date))
        let hour = String(format: "%02d", cal.component(.hour, from: date))
        let minute = String(format: "%02d", cal.component(.minute, from: date))
        let second = String(format: "%02d", cal.component(.second, from: date))

        var items: [MultiRenameItem] = []

        for (index, url) in urls.enumerated() {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let oldName = url.lastPathComponent
            let oldExt = isDir ? "" : url.pathExtension
            let oldBase = isDir || oldExt.isEmpty ? oldName : url.deletingPathExtension().lastPathComponent

            // Calculate counter
            let counterVal = options.counterStart + (index * options.counterStep)
            let counterStr = String(format: "%0\(max(1, options.counterDigits))d", counterVal)

            // 1. Process Name Pattern
            var name = options.namePattern
            name = name.replacingOccurrences(of: "[N]", with: oldBase)
            name = name.replacingOccurrences(of: "[C]", with: counterStr)
            name = name.replacingOccurrences(of: "[Y]", with: year)
            name = name.replacingOccurrences(of: "[M]", with: month)
            name = name.replacingOccurrences(of: "[D]", with: day)
            name = name.replacingOccurrences(of: "[h]", with: hour)
            name = name.replacingOccurrences(of: "[m]", with: minute)
            name = name.replacingOccurrences(of: "[s]", with: second)

            // Substring tags like [N1-5]
            if let regexN = try? NSRegularExpression(pattern: #"\[N([0-9]+)-([0-9]+)\]"#) {
                let matches = regexN.matches(in: name, range: NSRange(name.startIndex..., in: name))
                for m in matches.reversed() {
                    if let r1 = Range(m.range(at: 1), in: name), let startIdx = Int(name[r1]),
                       let r2 = Range(m.range(at: 2), in: name), let endIdx = Int(name[r2]) {
                        let clampedStart = max(1, startIdx) - 1
                        let clampedEnd = min(oldBase.count, endIdx)
                        let sub: String
                        if clampedStart < oldBase.count && clampedStart < clampedEnd {
                            let s = oldBase.index(oldBase.startIndex, offsetBy: clampedStart)
                            let e = oldBase.index(oldBase.startIndex, offsetBy: clampedEnd)
                            sub = String(oldBase[s..<e])
                        } else {
                            sub = ""
                        }
                        if let fullRange = Range(m.range, in: name) {
                            name.replaceSubrange(fullRange, with: sub)
                        }
                    }
                }
            }

            // 2. Process Extension Pattern
            var ext = options.extPattern
            if !isDir {
                ext = ext.replacingOccurrences(of: "[E]", with: oldExt)
                ext = ext.replacingOccurrences(of: "[C]", with: counterStr)
            } else {
                ext = ""
            }

            // Assemble full file name
            var fullName = ext.isEmpty ? name : "\(name).\(ext)"

            // 3. Search and Replace
            if !options.search.isEmpty {
                if options.useRegex {
                    if let reg = try? NSRegularExpression(pattern: options.search, options: options.caseSensitive ? [] : [.caseInsensitive]) {
                        fullName = reg.stringByReplacingMatches(in: fullName, options: [], range: NSRange(fullName.startIndex..., in: fullName), withTemplate: options.replace)
                    }
                } else {
                    let compareOptions: NSString.CompareOptions = options.caseSensitive ? [] : [.caseInsensitive]
                    fullName = fullName.replacingOccurrences(of: options.search, with: options.replace, options: compareOptions)
                }
            }

            // 4. Case Conversion
            switch options.caseConversion {
            case .none:
                break
            case .uppercase:
                fullName = fullName.uppercased()
            case .lowercase:
                fullName = fullName.lowercased()
            case .firstCapital:
                if let first = fullName.first {
                    fullName = String(first).uppercased() + fullName.dropFirst().lowercased()
                }
            case .titleCase:
                fullName = fullName.capitalized
            }

            // Validate name
            var err: String?
            do {
                try FileTasks.validateName(fullName)
            } catch {
                err = error.localizedDescription
            }

            items.append(MultiRenameItem(sourceURL: url, oldName: oldName, newName: fullName, error: err))
        }

        // Check for duplicate target names
        var seenTargets = [String: Int]()
        for item in items where item.error == nil {
            let key = item.newName.lowercased()
            seenTargets[key, default: 0] += 1
        }
        for (i, item) in items.enumerated() where item.error == nil {
            let key = item.newName.lowercased()
            if seenTargets[key]! > 1 {
                items[i].error = L("Şablon birden fazla dosyaya aynı adı veriyor.")
            }
        }

        return items
    }
}

final class MultiRenameWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let urls: [URL]
    private var items: [MultiRenameItem] = []
    var onApplied: (() -> Void)?

    private let namePatternField = NSTextField()
    private let extPatternField = NSTextField()
    private let searchField = NSTextField()
    private let replaceField = NSTextField()
    private let regexCheck = NSButton(checkboxWithTitle: L("Düzenli İfade (Regex)"), target: nil, action: nil)
    private let caseCheck = NSButton(checkboxWithTitle: L("Büyük/Küçük Harf Duyarlı"), target: nil, action: nil)
    private let casePopup = NSPopUpButton()
    private let startField = NSTextField()
    private let stepField = NSTextField()
    private let digitsField = NSTextField()

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(urls: [URL]) {
        self.urls = urls
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Çoklu Yeniden Adlandırma (Multi-Rename)")
        win.minSize = NSSize(width: 740, height: 500)
        super.init(window: win)

        setupUI()
        updatePreview()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        namePatternField.stringValue = "[N]"
        extPatternField.stringValue = "[E]"
        startField.stringValue = "1"
        stepField.stringValue = "1"
        digitsField.stringValue = "1"

        for f in [namePatternField, extPatternField, searchField, replaceField, startField, stepField, digitsField] {
            f.target = self
            f.action = #selector(inputChanged)
            f.delegate = self
        }

        regexCheck.target = self
        regexCheck.action = #selector(inputChanged)
        caseCheck.target = self
        caseCheck.action = #selector(inputChanged)

        for c in RenameCaseConversion.allCases {
            casePopup.addItem(withTitle: c.title)
        }
        casePopup.target = self
        casePopup.action = #selector(inputChanged)

        // Helper buttons for tags
        let tagN = tagButton("[N]", L("Ad")) { [weak self] in self?.appendTag("[N]") }
        let tagE = tagButton("[E]", L("Uzantı")) { [weak self] in self?.appendTag("[E]") }
        let tagC = tagButton("[C]", L("Sayaç")) { [weak self] in self?.appendTag("[C]") }
        let tagDate = tagButton("[YMD]", L("Tarih")) { [weak self] in self?.appendTag("[Y][M][D]") }
        let tagRow = NSStackView(views: [tagN, tagE, tagC, tagDate])
        tagRow.spacing = 6

        // Grid 1: Patterns
        let grid1 = NSGridView(views: [
            [label(L("Ad Şablonu:")), namePatternField, tagRow],
            [label(L("Uzantı:")), extPatternField, NSView()]
        ])
        grid1.columnSpacing = 10
        grid1.rowSpacing = 6

        // Grid 2: Search & Replace
        let grid2 = NSGridView(views: [
            [label(L("Ara:")), searchField, regexCheck],
            [label(L("Değiştir:")), replaceField, caseCheck]
        ])
        grid2.columnSpacing = 10
        grid2.rowSpacing = 6

        // Grid 3: Case & Counter
        startField.widthAnchor.constraint(equalToConstant: 45).isActive = true
        stepField.widthAnchor.constraint(equalToConstant: 45).isActive = true
        digitsField.widthAnchor.constraint(equalToConstant: 45).isActive = true

        let counterRow = NSStackView(views: [
            labelSmall(L("Başla:")), startField,
            labelSmall(L("Adım:")), stepField,
            labelSmall(L("Basamak:")), digitsField
        ])
        counterRow.spacing = 4

        let grid3 = NSGridView(views: [
            [label(L("Harf Durumu:")), casePopup],
            [label(L("Sayaç Ayarları:")), counterRow]
        ])
        grid3.columnSpacing = 10
        grid3.rowSpacing = 6

        let topBox = NSStackView(views: [grid1, grid2, grid3])
        topBox.orientation = .vertical
        topBox.spacing = 8
        topBox.translatesAutoresizingMaskIntoConstraints = false

        // Table View
        let colOld = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("old"))
        colOld.title = L("Eski Ad")
        colOld.width = 340
        tableView.addTableColumn(colOld)

        let colNew = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("new"))
        colNew.title = L("Yeni Ad")
        colNew.width = 360
        tableView.addTableColumn(colNew)

        let colStatus = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        colStatus.title = L("Durum")
        colStatus.width = 110
        tableView.addTableColumn(colStatus)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 20
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Buttons
        let applyBtn = NSButton(title: L("Uygula"), target: self, action: #selector(applyClicked))
        applyBtn.keyEquivalent = "\r"
        let closeBtn = NSButton(title: L("Kapat"), target: self, action: #selector(closeClicked))

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let bottomRow = NSStackView(views: [statusLabel, NSView(), closeBtn, applyBtn])
        bottomRow.spacing = 8
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [topBox, scroll, bottomRow])
        rootV.orientation = .vertical
        rootV.spacing = 10
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            topBox.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: rootV.widthAnchor),
            bottomRow.widthAnchor.constraint(equalTo: rootV.widthAnchor)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.widthAnchor.constraint(equalToConstant: 105).isActive = true
        return l
    }

    private func labelSmall(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11)
        return l
    }

    private func tagButton(_ tag: String, _ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: "\(tag) \(title)", target: nil, action: nil)
        b.bezelStyle = .inline
        b.font = .systemFont(ofSize: 11)
        b.target = self
        let sel = #selector(tagClicked(_:))
        b.action = sel
        b.identifier = NSUserInterfaceItemIdentifier(tag)
        return b
    }

    @objc private func tagClicked(_ sender: NSButton) {
        appendTag(sender.identifier?.rawValue ?? "")
    }

    private func appendTag(_ tag: String) {
        namePatternField.stringValue += tag
        updatePreview()
    }

    @objc private func inputChanged() {
        updatePreview()
    }

    private func updatePreview() {
        let options = MultiRenameOptions(
            namePattern: namePatternField.stringValue,
            extPattern: extPatternField.stringValue,
            search: searchField.stringValue,
            replace: replaceField.stringValue,
            useRegex: regexCheck.state == .on,
            caseSensitive: caseCheck.state == .on,
            caseConversion: RenameCaseConversion(rawValue: casePopup.indexOfSelectedItem) ?? .none,
            counterStart: Int(startField.stringValue) ?? 1,
            counterStep: Int(stepField.stringValue) ?? 1,
            counterDigits: Int(digitsField.stringValue) ?? 1
        )

        items = MultiRenameEngine.generateNames(urls: urls, options: options)
        tableView.reloadData()

        let willChangeCount = items.filter(\.willChange).count
        let errorCount = items.filter { $0.error != nil }.count

        if errorCount > 0 {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = L("{0} dosyada ad çakışması veya geçersiz ad var.", errorCount)
        } else {
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = L("{0} dosya yeniden adlandırılacak.", willChangeCount)
        }
    }

    @objc private func applyClicked() {
        let errors = items.compactMap(\.error)
        guard errors.isEmpty else {
            let a = NSAlert()
            a.messageText = L("Adlandırma Hataları")
            a.informativeText = errors.first ?? ""
            a.runModal()
            return
        }

        let plan = items.filter(\.willChange).map { item in
            RenamePlan(source: item.sourceURL, destination: item.sourceURL.deletingLastPathComponent().appendingPathComponent(item.newName))
        }

        guard !plan.isEmpty else {
            window?.close()
            return
        }

        do {
            try FileTasks.rename(plan)
            window?.close()
            onApplied!()
        } catch {
            let a = NSAlert()
            a.messageText = L("Hata")
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func closeClicked() {
        window?.close()
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue, items.indices.contains(row) else { return nil }
        let item = items[row]

        let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(colId), owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
        cell.identifier = NSUserInterfaceItemIdentifier(colId)
        cell.font = .systemFont(ofSize: 11)

        switch colId {
        case "old":
            cell.stringValue = item.oldName
            cell.textColor = .secondaryLabelColor
        case "new":
            cell.stringValue = item.newName
            cell.textColor = item.error != nil ? .systemRed : (item.willChange ? .systemGreen : .labelColor)
        case "status":
            if let err = item.error {
                cell.stringValue = err
                cell.textColor = .systemRed
            } else if item.willChange {
                cell.stringValue = L("Değişecek")
                cell.textColor = .systemGreen
            } else {
                cell.stringValue = L("Aynı")
                cell.textColor = .tertiaryLabelColor
            }
        default:
            break
        }

        return cell
    }
}

extension MultiRenameWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updatePreview()
    }
}
