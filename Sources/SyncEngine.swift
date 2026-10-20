// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation
import CryptoKit

enum SyncDirection: String, Equatable {
    case copyRight = "->"
    case copyLeft = "<-"
    case equal = "="
    case conflict = "≠"
    case deleteRight = "x"

    var localizedTitle: String {
        switch self {
        case .copyRight: return L("Sağa kopyala")
        case .copyLeft: return L("Sola kopyala")
        case .equal: return L("Eşit")
        case .conflict: return L("Çakışma")
        case .deleteRight: return L("Sağdakini sil")
        }
    }
}

struct SyncItem: Equatable {
    let relativePath: String
    let isDirectory: Bool
    let leftURL: URL?
    let leftSize: Int64?
    let leftDate: Date?
    var direction: SyncDirection
    let rightURL: URL?
    let rightSize: Int64?
    let rightDate: Date?

    var isActionable: Bool {
        direction == .copyRight || direction == .copyLeft || direction == .deleteRight
    }
}

struct SyncOptions {
    var subdirs: Bool = true
    var byContent: Bool = false
    var ignoreDate: Bool = false
    var asymmetric: Bool = false
}

final class SyncEngine {
    static func fileHash(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func compareDirectories(left: URL, right: URL, options: SyncOptions, control: JobState = JobState(), progress: ((Int, String) -> Void)? = nil) throws -> [SyncItem] {
        try FileTasks.validateTransfer([left], to: right)
        let fm = FileManager.default

        var leftMap: [String: (url: URL, size: Int64, date: Date, isDir: Bool)] = [:]
        var rightMap: [String: (url: URL, size: Int64, date: Date, isDir: Bool)] = [:]

        func scan(dir: URL, into: inout [String: (url: URL, size: Int64, date: Date, isDir: Bool)]) throws {
            let dirStd = dir.resolvingSymlinksInPath().standardizedFileURL.path
            let basePrefix = dirStd.hasSuffix("/") ? dirStd : (dirStd + "/")
            let enumerator = fm.enumerator(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: options.subdirs ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants])

            while let fileURL = enumerator?.nextObject() as? URL {
                if control.cancelled { throw PanelError(message: L("Eşitleme planı iptal edildi.")) }
                let vals = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDir = vals.isDirectory ?? false
                let fullPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard fullPath.hasPrefix(basePrefix) else { continue }
                let rel = String(fullPath.dropFirst(basePrefix.count))
                into[rel] = (fileURL, Int64(vals.fileSize ?? 0), vals.contentModificationDate ?? .distantPast, isDir)
            }
        }

        try scan(dir: left, into: &leftMap)
        try scan(dir: right, into: &rightMap)

        let allKeys = Set(leftMap.keys).union(rightMap.keys).sorted()
        var items: [SyncItem] = []

        for (idx, key) in allKeys.enumerated() {
            if control.cancelled { throw PanelError(message: L("Eşitleme planı iptal edildi.")) }
            progress?(idx, key)

            let l = leftMap[key]
            let r = rightMap[key]

            if let l = l, r == nil {
                // Exists only on left
                let item = SyncItem(
                    relativePath: key,
                    isDirectory: l.isDir,
                    leftURL: l.url,
                    leftSize: l.size,
                    leftDate: l.date,
                    direction: .copyRight,
                    rightURL: right.appendingPathComponent(key),
                    rightSize: nil,
                    rightDate: nil
                )
                items.append(item)
            } else if l == nil, let r = r {
                // Exists only on right
                let dir: SyncDirection = options.asymmetric ? .deleteRight : .copyLeft
                let item = SyncItem(
                    relativePath: key,
                    isDirectory: r.isDir,
                    leftURL: left.appendingPathComponent(key),
                    leftSize: nil,
                    leftDate: nil,
                    direction: dir,
                    rightURL: r.url,
                    rightSize: r.size,
                    rightDate: r.date
                )
                items.append(item)
            } else if let l = l, let r = r {
                // Exists on both sides
                if l.isDir && r.isDir {
                    continue // directory itself is equal
                }

                var dir: SyncDirection = .conflict

                if l.size == r.size {
                    if options.byContent {
                        let lHash = fileHash(url: l.url)
                        let rHash = fileHash(url: r.url)
                        if lHash != nil && lHash == rHash {
                            dir = .equal
                        } else {
                            let diff = l.date.timeIntervalSince(r.date)
                            dir = diff > 2 ? .copyRight : (diff < -2 ? .copyLeft : .conflict)
                        }
                    } else if options.ignoreDate || abs(l.date.timeIntervalSince(r.date)) < 2 {
                        dir = .equal
                    } else {
                        let diff = l.date.timeIntervalSince(r.date)
                        dir = diff > 2 ? .copyRight : (diff < -2 ? .copyLeft : .conflict)
                    }
                } else {
                    let diff = l.date.timeIntervalSince(r.date)
                    dir = diff > 2 ? .copyRight : (diff < -2 ? .copyLeft : .conflict)
                }

                let item = SyncItem(
                    relativePath: key,
                    isDirectory: false,
                    leftURL: l.url,
                    leftSize: l.size,
                    leftDate: l.date,
                    direction: dir,
                    rightURL: r.url,
                    rightSize: r.size,
                    rightDate: r.date
                )
                items.append(item)
            }
        }

        return items
    }

    static func executeSync(items: [SyncItem], control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        let fm = FileManager.default
        let actionable = items.filter(\.isActionable)
        guard !actionable.isEmpty else { return }

        for (idx, item) in actionable.enumerated() {
            if control.cancelled { throw PanelError(message: L("Eşitleme iptal edildi. Tamamlanan değişiklikler korundu.")) }
            progress(idx, actionable.count, item.relativePath)

            switch item.direction {
            case .copyRight:
                guard let src = item.leftURL, let dst = item.rightURL else { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) {
                    let backup = FileTasks.unique(dst.deletingLastPathComponent().appendingPathComponent(dst.lastPathComponent + ".totalcommand-backup"))
                    try? fm.moveItem(at: dst, to: backup)
                }
                try FileTasks.transfer([src], to: dst.deletingLastPathComponent(), move: false, cancelled: { control.cancelled }, progress: { _, _, _ in })

            case .copyLeft:
                guard let src = item.rightURL, let dst = item.leftURL else { continue }
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) {
                    let backup = FileTasks.unique(dst.deletingLastPathComponent().appendingPathComponent(dst.lastPathComponent + ".totalcommand-backup"))
                    try? fm.moveItem(at: dst, to: backup)
                }
                try FileTasks.transfer([src], to: dst.deletingLastPathComponent(), move: false, cancelled: { control.cancelled }, progress: { _, _, _ in })

            case .deleteRight:
                if let dst = item.rightURL, fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }

            default:
                break
            }

            progress(idx + 1, actionable.count, item.relativePath)
        }
    }
}
