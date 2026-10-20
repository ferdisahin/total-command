// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation
import Cocoa

final class CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private var crc: UInt32 = 0xFFFFFFFF

    func update(data: Data) {
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<buffer.count {
                let index = Int((crc ^ UInt32(ptr[i])) & 0xFF)
                crc = (crc >> 8) ^ CRC32.table[index]
            }
        }
    }

    var checksum: UInt32 {
        crc ^ 0xFFFFFFFF
    }

    var hexString: String {
        String(format: "%08X", checksum)
    }

    static func calculate(data: Data) -> String {
        let c = CRC32()
        c.update(data: data)
        return c.hexString
    }
}

final class FileSplitter {
    static func split(source: URL, destinationDir: URL, chunkSize: Int64, generateCRC: Bool, control: JobState, progress: @escaping (Int64, Int64, String) -> Void) throws -> [URL] {
        guard chunkSize > 0 else { throw PanelError(message: L("Parça boyutu sıfırdan büyük olmalıdır.")) }
        let totalSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard totalSize > 0 else { throw PanelError(message: L("Boş dosya bölünemez.")) }

        let readHandle = try FileHandle(forReadingFrom: source)
        defer { try? readHandle.close() }

        let originalName = source.lastPathComponent
        let crc = CRC32()
        var createdParts: [URL] = []
        var partIndex = 1
        var totalBytesRead: Int64 = 0

        let bufferSize = 256 * 1024 // 256 KB
        var currentPartBytes: Int64 = 0
        var writeHandle: FileHandle?

        func finishCurrentPart() {
            try? writeHandle?.close()
            writeHandle = nil
            currentPartBytes = 0
        }

        do {
            while totalBytesRead < totalSize {
                if control.cancelled {
                    finishCurrentPart()
                    for p in createdParts { try? FileManager.default.removeItem(at: p) }
                    throw PanelError(message: L("Bölme işlemi iptal edildi."))
                }

                if writeHandle == nil {
                    let partName = String(format: "%@.%03d", originalName, partIndex)
                    let partURL = destinationDir.appendingPathComponent(partName)
                    FileManager.default.createFile(atPath: partURL.path, contents: nil)
                    writeHandle = try FileHandle(forWritingTo: partURL)
                    createdParts.append(partURL)
                    partIndex += 1
                }

                let remainingInChunk = chunkSize - currentPartBytes
                let readAmount = min(Int64(bufferSize), min(remainingInChunk, totalSize - totalBytesRead))
                guard readAmount > 0, let chunkData = try? readHandle.read(upToCount: Int(readAmount)), !chunkData.isEmpty else {
                    break
                }

                if generateCRC {
                    crc.update(data: chunkData)
                }

                try writeHandle?.write(contentsOf: chunkData)
                currentPartBytes += Int64(chunkData.count)
                totalBytesRead += Int64(chunkData.count)

                progress(totalBytesRead, totalSize, source.lastPathComponent)

                if currentPartBytes >= chunkSize {
                    finishCurrentPart()
                }
            }
            finishCurrentPart()

            if generateCRC && !control.cancelled {
                let crcContent = "filename=\(originalName)\nsize=\(totalSize)\ncrc32=\(crc.hexString)\n"
                let crcURL = destinationDir.appendingPathComponent("\(originalName).crc")
                try crcContent.write(to: crcURL, atomically: true, encoding: .utf8)
                createdParts.append(crcURL)
            }
        } catch {
            finishCurrentPart()
            for p in createdParts { try? FileManager.default.removeItem(at: p) }
            throw error
        }

        return createdParts
    }

    static func detectParts(firstPart: URL) -> (parts: [URL], originalName: String, crcURL: URL?) {
        let folder = firstPart.deletingLastPathComponent()
        let name = firstPart.lastPathComponent
        guard name.hasSuffix(".001") else { return ([], name, nil) }

        let originalName = String(name.dropLast(4)) // drop .001
        var parts: [URL] = []
        var idx = 1

        while true {
            let candidateName = String(format: "%@.%03d", originalName, idx)
            let candidateURL = folder.appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                parts.append(candidateURL)
                idx += 1
            } else {
                break
            }
        }

        let crcURL = folder.appendingPathComponent("\(originalName).crc")
        let hasCRC = FileManager.default.fileExists(atPath: crcURL.path) ? crcURL : nil

        return (parts, originalName, hasCRC)
    }

    static func combine(parts: [URL], originalName: String, destinationDir: URL, crcURL: URL?, verifyCRC: Bool, control: JobState, progress: @escaping (Int64, Int64, String) -> Void) throws -> URL {
        guard !parts.isEmpty else { throw PanelError(message: L("Birleştirilecek parça bulunamadı.")) }

        var totalSize: Int64 = 0
        for p in parts {
            totalSize += (try? p.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }

        let targetURL = FileTasks.unique(destinationDir.appendingPathComponent(originalName))
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        let writeHandle = try FileHandle(forWritingTo: targetURL)
        defer { try? writeHandle.close() }

        let crc = CRC32()
        var totalBytesWritten: Int64 = 0
        let bufferSize = 256 * 1024

        for part in parts {
            if control.cancelled {
                try? writeHandle.close()
                try? FileManager.default.removeItem(at: targetURL)
                throw PanelError(message: L("Birleştirme işlemi iptal edildi."))
            }

            let readHandle = try FileHandle(forReadingFrom: part)
            defer { try? readHandle.close() }

            while true {
                if control.cancelled {
                    try? writeHandle.close()
                    try? FileManager.default.removeItem(at: targetURL)
                    throw PanelError(message: L("Birleştirme işlemi iptal edildi."))
                }

                guard let chunk = try? readHandle.read(upToCount: bufferSize), !chunk.isEmpty else {
                    break
                }

                if verifyCRC {
                    crc.update(data: chunk)
                }

                try writeHandle.write(contentsOf: chunk)
                totalBytesWritten += Int64(chunk.count)
                progress(totalBytesWritten, totalSize, part.lastPathComponent)
            }
        }

        if verifyCRC, let crcFile = crcURL, let content = try? String(contentsOf: crcFile, encoding: .utf8) {
            var expectedCRC: String?
            for line in content.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=")
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "crc32" {
                    expectedCRC = parts[1].trimmingCharacters(in: .whitespaces).uppercased()
                }
            }
            if let expected = expectedCRC, expected != crc.hexString {
                try? FileManager.default.removeItem(at: targetURL)
                throw PanelError(message: L("CRC32 doğrulama hatası! Beklenen: {0}, Hesaplanan: {1}", expected, crc.hexString))
            }
        }

        return targetURL
    }
}

final class SplitWindowController: NSWindowController {
    private let sourceURL: URL
    private let destinationDir: URL
    var onStartSplit: ((URL, URL, Int64, Bool) -> Void)?

    private let sizePopup = NSPopUpButton()
    private let customField = NSTextField()
    private let customUnitPopup = NSPopUpButton()
    private let crcCheck = NSButton(checkboxWithTitle: L("Total Commander uyumlu CRC32 doğrulama dosyası (.crc) oluştur"), target: nil, action: nil)

    private let presets: [(String, Int64)] = [
        (L("1.44 MB (3.5 inç Disket)"), 1_457_664),
        (L("100 MB (ZIP disk)"), 100_431_872),
        (L("250 MB (ZIP disk)"), 250_331_136),
        (L("650 MB (CD-ROM)"), 681_574_400),
        (L("700 MB (CD-ROM)"), 734_003_200),
        (L("1 GB"), 1_073_741_824),
        (L("4.7 GB (DVD)"), 4_700_000_000),
        (L("Özel Boyut"), -1)
    ]

    init(sourceURL: URL, destinationDir: URL) {
        self.sourceURL = sourceURL
        self.destinationDir = destinationDir

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Dosyayı Parçalara Böl")
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        for (title, _) in presets {
            sizePopup.addItem(withTitle: title)
        }
        sizePopup.selectItem(at: 3) // 650 MB default
        sizePopup.target = self
        sizePopup.action = #selector(presetChanged)

        customField.stringValue = "50"
        customField.isEnabled = false
        customField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        for unit in ["MB", "KB", "GB", L("Bayt")] {
            customUnitPopup.addItem(withTitle: unit)
        }
        customUnitPopup.isEnabled = false

        crcCheck.state = .on

        let sizeRow = NSStackView(views: [sizePopup, customField, customUnitPopup])
        sizeRow.spacing = 8

        let totalSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)

        let grid = NSGridView(views: [
            [label(L("Kaynak Dosya:")), valueLabel("\(sourceURL.lastPathComponent) (\(sizeStr))")],
            [label(L("Hedef Klasör:")), valueLabel(destinationDir.path)],
            [label(L("Parça Boyutu:")), sizeRow]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let splitBtn = NSButton(title: L("Böl"), target: self, action: #selector(splitClicked))
        splitBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: L("İptal"), target: self, action: #selector(cancelClicked))

        let btnRow = NSStackView(views: [NSView(), cancelBtn, splitBtn])
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [grid, crcCheck, btnRow])
        rootV.orientation = .vertical
        rootV.spacing = 14
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            grid.widthAnchor.constraint(equalTo: rootV.widthAnchor),
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

    private func valueLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }

    @objc private func presetChanged() {
        let isCustom = sizePopup.indexOfSelectedItem == presets.count - 1
        customField.isEnabled = isCustom
        customUnitPopup.isEnabled = isCustom
    }

    @objc private func splitClicked() {
        let selectedIdx = sizePopup.indexOfSelectedItem
        var sizeBytes = presets[selectedIdx].1

        if sizeBytes == -1 {
            let val = Double(customField.stringValue) ?? 10
            let unit = customUnitPopup.selectedItem?.title ?? "MB"
            switch unit {
            case "KB": sizeBytes = Int64(val * 1024)
            case "GB": sizeBytes = Int64(val * 1024 * 1024 * 1024)
            case L("Bayt"): sizeBytes = Int64(val)
            default: sizeBytes = Int64(val * 1024 * 1024) // MB
            }
        }

        window?.close()
        onStartSplit?(sourceURL, destinationDir, sizeBytes, crcCheck.state == .on)
    }

    @objc private func cancelClicked() {
        window?.close()
    }
}

final class CombineWindowController: NSWindowController {
    private let parts: [URL]
    private let originalName: String
    private let destinationDir: URL
    private let crcURL: URL?
    var onStartCombine: (([URL], String, URL, URL?, Bool) -> Void)?

    private let nameField = NSTextField()
    private let crcCheck = NSButton(checkboxWithTitle: L("CRC32 doğrulama dosyasını (.crc) kontrol et"), target: nil, action: nil)

    init(parts: [URL], originalName: String, destinationDir: URL, crcURL: URL?) {
        self.parts = parts
        self.originalName = originalName
        self.destinationDir = destinationDir
        self.crcURL = crcURL

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L("Dosyaları Birleştir")
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        nameField.stringValue = originalName

        var totalSize: Int64 = 0
        for p in parts {
            totalSize += (try? p.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)

        crcCheck.state = crcURL != nil ? .on : .off
        crcCheck.isEnabled = crcURL != nil

        let grid = NSGridView(views: [
            [label(L("Parça Sayısı:")), valueLabel(L("{0} parça bulundu ({1})", parts.count, sizeStr))],
            [label(L("Hedef Klasör:")), valueLabel(destinationDir.path)],
            [label(L("Çıktı Dosyası:")), nameField]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let combineBtn = NSButton(title: L("Birleştir"), target: self, action: #selector(combineClicked))
        combineBtn.keyEquivalent = "\r"
        let cancelBtn = NSButton(title: L("İptal"), target: self, action: #selector(cancelClicked))

        let btnRow = NSStackView(views: [NSView(), cancelBtn, combineBtn])
        btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        let rootV = NSStackView(views: [grid, crcCheck, btnRow])
        rootV.orientation = .vertical
        rootV.spacing = 14
        rootV.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootV)

        NSLayoutConstraint.activate([
            rootV.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            rootV.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rootV.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rootV.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            grid.widthAnchor.constraint(equalTo: rootV.widthAnchor),
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

    private func valueLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }

    @objc private func combineClicked() {
        let outName = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !outName.isEmpty else { return }
        window?.close()
        onStartCombine?(parts, outName, destinationDir, crcURL, crcCheck.state == .on)
    }

    @objc private func cancelClicked() {
        window?.close()
    }
}
