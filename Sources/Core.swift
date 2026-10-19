// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

struct PanelError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct RenamePlan {
    let source: URL
    let destination: URL
    static func make(_ urls: [URL], pattern: String, start: Int) throws -> [RenamePlan] {
        guard !pattern.isEmpty else { throw PanelError(message: "Ad şablonu boş olamaz.") }
        let plan = try urls.enumerated().map { index, url -> RenamePlan in
            let ext = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "" : url.pathExtension
            let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            var name = pattern.replacingOccurrences(of: "[N]", with: base).replacingOccurrences(of: "[E]", with: ext).replacingOccurrences(of: "[C]", with: String(start + index))
            if ext.isEmpty && pattern.hasSuffix(".[E]") && name.hasSuffix(".") { name.removeLast() }
            try FileTasks.validateName(name)
            return RenamePlan(source: url, destination: url.deletingLastPathComponent().appendingPathComponent(name))
        }
        let targets = plan.map { $0.destination.path.lowercased() }
        guard Set(targets).count == targets.count else { throw PanelError(message: "Şablon birden fazla dosyaya aynı adı veriyor.") }
        for row in plan where row.source != row.destination {
            if FileManager.default.fileExists(atPath: row.destination.path) { throw PanelError(message: "Hedef zaten var: \(row.destination.lastPathComponent)") }
        }
        return plan
    }
}
final class FileTasks {
    static let fm = FileManager.default
    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else { throw PanelError(message: "Geçerli bir dosya adı girin.") }
    }
    static func unique(_ target: URL) -> URL {
        if !fm.fileExists(atPath: target.path) { return target }
        var n = 2
        while true {
            let ext = target.pathExtension
            let base = ext.isEmpty ? target.lastPathComponent : target.deletingPathExtension().lastPathComponent
            let name = "\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)")
            let next = target.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: next.path) { return next }; n += 1
        }
    }
    static func validateTransfer(_ sources: [URL], to destination: URL) throws {
        let dest = destination.resolvingSymlinksInPath().standardizedFileURL.path
        for source in sources {
            let src = source.resolvingSymlinksInPath().standardizedFileURL.path
            if dest == src || dest.hasPrefix(src + "/") { throw PanelError(message: "Bir klasör kendi içine kopyalanamaz veya taşınamaz.") }
            if source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == dest { throw PanelError(message: "Kaynak ve hedef klasör aynı.") }
        }
    }
    static func transfer(_ sources: [URL], to destination: URL, move: Bool, cancelled: () -> Bool, progress: (Int, Int, String) -> Void) throws {
        try validateTransfer(sources, to: destination)
        for (index, source) in sources.enumerated() {
            if cancelled() { throw PanelError(message: "İşlem iptal edildi. Tamamlanan dosyalar hedefte kaldı.") }
            progress(index, sources.count, source.lastPathComponent)
            let target = unique(destination.appendingPathComponent(source.lastPathComponent))
            if move { try fm.moveItem(at: source, to: target) }
            else {
                let staging = destination.appendingPathComponent(".panelmac-" + UUID().uuidString)
                do {
                    try copy(source, to: staging, cancelled: cancelled)
                    try fm.moveItem(at: staging, to: target)
                } catch { try? fm.removeItem(at: staging); throw error }
            }
            progress(index + 1, sources.count, source.lastPathComponent)
        }
    }
    private static func copy(_ source: URL, to target: URL, cancelled: () -> Bool) throws {
        if cancelled() { throw PanelError(message: "Kopyalama iptal edildi.") }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { try fm.copyItem(at: source, to: target); return }
        if values.isDirectory == true {
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) { try copy(child, to: target.appendingPathComponent(child.lastPathComponent), cancelled: cancelled) }
            if let attrs = try? fm.attributesOfItem(atPath: source.path) { try? fm.setAttributes([.posixPermissions: attrs[.posixPermissions] ?? 0o755, .modificationDate: attrs[.modificationDate] ?? Date()], ofItemAtPath: target.path) }
        } else {
            // copyfile preserves macOS metadata; cancellation is checked between files.
            try fm.copyItem(at: source, to: target)
        }
    }
    static func rename(_ plan: [RenamePlan]) throws {
        var completed: [RenamePlan] = []
        do { for row in plan where row.source != row.destination { try fm.moveItem(at: row.source, to: row.destination); completed.append(row) } }
        catch { for row in completed.reversed() { try? fm.moveItem(at: row.destination, to: row.source) }; throw error }
    }
    static func validateArchivePaths(_ listing: String) throws {
        for path in listing.split(separator: "\n") {
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") { throw PanelError(message: "Arşiv güvenli olmayan bir dosya yolu içeriyor: \(path)") }
        }
    }
}

struct SyncChange {
    let source: URL
    let target: URL
    let exists: Bool
}
extension FileTasks {
    static func syncPlan(from source: URL, to target: URL, includeHidden: Bool, cancelled: () -> Bool = { false }) throws -> [SyncChange] {
        try validateTransfer([source], to: target)
        var changes: [SyncChange] = []
        func visit(_ src: URL, _ dst: URL) throws {
            if cancelled() { throw PanelError(message: "Eşitleme planı iptal edildi.") }
            let a = try src.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            let b = try? dst.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            let exists = fm.fileExists(atPath: dst.path) || b?.isSymbolicLink == true
            if a.isDirectory == true && a.isSymbolicLink != true && b?.isDirectory == true && b?.isSymbolicLink != true {
                for child in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: includeHidden ? [] : [.skipsHiddenFiles]) { try visit(child, dst.appendingPathComponent(child.lastPathComponent)) }
            } else {
                let equal = exists && a.isDirectory == b?.isDirectory && a.isSymbolicLink == b?.isSymbolicLink && a.fileSize == b?.fileSize && abs((a.contentModificationDate ?? .distantPast).timeIntervalSince(b?.contentModificationDate ?? .distantFuture)) < 2
                if !equal { changes.append(SyncChange(source: src, target: dst, exists: exists)) }
            }
        }
        for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: includeHidden ? [] : [.skipsHiddenFiles]) { try visit(child, target.appendingPathComponent(child.lastPathComponent)) }
        return changes
    }
    static func applySync(_ changes: [SyncChange], cancelled: () -> Bool, progress: (Int, Int, String) -> Void) throws {
        for (i, change) in changes.enumerated() {
            if cancelled() { throw PanelError(message: "Eşitleme iptal edildi. Tamamlanan değişiklikler korundu.") }
            var backup: URL?
            if change.exists {
                let candidate = unique(change.target.deletingLastPathComponent().appendingPathComponent(change.target.lastPathComponent + ".totalcommand-backup"))
                try fm.moveItem(at: change.target, to: candidate); backup = candidate
            }
            do { try transfer([change.source], to: change.target.deletingLastPathComponent(), move: false, cancelled: cancelled, progress: { _,_,_ in }) }
            catch { if let backup { try? fm.moveItem(at: backup, to: change.target) }; throw error }
            progress(i + 1, changes.count, change.source.lastPathComponent)
        }
    }
}
