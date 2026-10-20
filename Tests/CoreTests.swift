// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation
@main struct Tests {
    static func main() throws {
        try testLocalization()
        testJobs()
        try testUpdates()
        RemoteTests.run()
        DiffTests.run()
        MultiRenameTests.run()
        let suite = "TotalCommand.Test." + UUID().uuidString
        Prefs.store = UserDefaults(suiteName: suite)!
        Prefs.register()
        assert(Prefs.string("appLanguage") == "system")
        Prefs.set("appLanguage", "tr"); assert(Prefs.string("appLanguage") == "tr")
        assert(Prefs.int("updateInterval") == 0 && !Prefs.bool("updatePreviews"))
        Prefs.set("updateInterval", 7); Prefs.set("updatePreviews", true)
        assert(Prefs.int("updateInterval") == 7 && Prefs.bool("updatePreviews"))
        assert(Prefs.int("fontSize") == 12 && Prefs.bool("confirmTrash"))
        Prefs.set("fontSize", 14); Prefs.set("restoreTabs", false); Prefs.set("keyF5", "rename")
        assert(Prefs.int("fontSize") == 14 && !Prefs.bool("restoreTabs") && Prefs.string("keyF5") == "rename")
        Prefs.store.synchronize()
        assert(UserDefaults(suiteName: suite)!.integer(forKey: "fontSize") == 14)
        Prefs.store.removePersistentDomain(forName: suite)
        assert(Prefs.string("appLanguage") == "system")
        assert(Prefs.int("updateInterval") == 0 && !Prefs.bool("updatePreviews"))
        assert(Prefs.int("fontSize") == 12)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("TotalCommand-Tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try fm.createDirectory(at: source, withIntermediateDirectories: false); try fm.createDirectory(at: target, withIntermediateDirectories: false)
        let file = source.appendingPathComponent("Türkçe boşluk.txt")
        let contents = Data("Merhaba dünya\n".utf8); try contents.write(to: file)
        try FileTasks.transfer([file], to: target, move: false, cancelled: { false }, progress: { _,_,_ in })
        let copied = try Data(contentsOf: target.appendingPathComponent(file.lastPathComponent)); assert(copied == contents)
        try FileTasks.transfer([file], to: target, move: false, cancelled: { false }, progress: { _,_,_ in })
        assert(fm.fileExists(atPath: target.appendingPathComponent("Türkçe boşluk (2).txt").path))
        let folder = source.appendingPathComponent("Folder"); try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try contents.write(to: folder.appendingPathComponent("child.txt"))
        try fm.createSymbolicLink(atPath: folder.appendingPathComponent("link").path, withDestinationPath: "child.txt")
        try FileTasks.transfer([folder], to: target, move: false, cancelled: { false }, progress: { _,_,_ in })
        let link = try fm.destinationOfSymbolicLink(atPath: target.appendingPathComponent("Folder/link").path); assert(link == "child.txt")
        func rejects(_ action: () throws -> Void) { do { try action(); fatalError("Expected rejection") } catch {} }
        rejects { try FileTasks.validateTransfer([folder], to: folder.appendingPathComponent("nested")) }
        rejects { try FileTasks.validateTransfer([file], to: source) }
        rejects { try FileTasks.transfer([file], to: target, move: false, cancelled: { true }, progress: { _,_,_ in }) }
        let plan = try RenamePlan.make([file], pattern: "[N]_[C].[E]", start: 1)
        try FileTasks.rename(plan); assert(fm.fileExists(atPath: source.appendingPathComponent("Türkçe boşluk_1.txt").path))
        rejects { _ = try RenamePlan.make([plan[0].destination, folder], pattern: "same", start: 1) }
        rejects { try FileTasks.validateName("../bad") }
        rejects { try FileTasks.validateArchivePaths("ok.txt\n../escape") }
        rejects { try FileTasks.validateArchivePaths("/absolute/path") }
        try FileTasks.validateArchivePaths("Folder/child.txt\nnormal.txt")
        try FileTasks.transfer([plan[0].destination], to: target, move: true, cancelled: { false }, progress: { _,_,_ in })
        assert(!fm.fileExists(atPath: plan[0].destination.path))
        let syncSource = root.appendingPathComponent("syncSource"), syncTarget = root.appendingPathComponent("syncTarget")
        try fm.createDirectory(at: syncSource, withIntermediateDirectories: false); try fm.createDirectory(at: syncTarget, withIntermediateDirectories: false)
        try Data("new contents".utf8).write(to: syncSource.appendingPathComponent("same.txt"))
        try Data("old".utf8).write(to: syncTarget.appendingPathComponent("same.txt"))
        try Data("keep".utf8).write(to: syncTarget.appendingPathComponent("extra.txt"))
        let syncPlan = try FileTasks.syncPlan(from: syncSource, to: syncTarget, includeHidden: false)
        assert(syncPlan.count == 1 && syncPlan[0].exists)
        try FileTasks.applySync(syncPlan, cancelled: { false }, progress: { _,_,_ in })
        let synced = try String(contentsOf: syncTarget.appendingPathComponent("same.txt"), encoding: .utf8)
        let backup = try String(contentsOf: syncTarget.appendingPathComponent("same.txt.totalcommand-backup"), encoding: .utf8)
        assert(synced == "new contents" && backup == "old" && fm.fileExists(atPath: syncTarget.appendingPathComponent("extra.txt").path))
        var calls = 0
        rejects { try FileTasks.transfer([folder], to: target, move: false, cancelled: { calls += 1; return calls > 2 }, progress: { _,_,_ in }) }
        let leftovers = try fm.contentsOfDirectory(atPath: target.path).filter { $0.hasPrefix(".panelmac-") }; assert(leftovers.isEmpty)
        let archiveDirectory = root.appendingPathComponent("archives")
        try fm.createDirectory(at: archiveDirectory, withIntermediateDirectories: false)
        try contents.write(to: archiveDirectory.appendingPathComponent("Türkçe boşluk.txt"))
        func tar(_ args: [String], at directory: URL) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar"); process.arguments = args; process.currentDirectoryURL = directory; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); assert(process.terminationStatus == 0)
        }
        for format in ["zip", "7zip"] {
            let archive = archiveDirectory.appendingPathComponent("test." + format)
            try tar(["--format", format, "-cf", archive.path, "--", "Türkçe boşluk.txt"], at: archiveDirectory)
            let out = archiveDirectory.appendingPathComponent(format); try fm.createDirectory(at: out, withIntermediateDirectories: false)
            try tar(["-xf", archive.path, "-C", out.path, "--no-same-owner", "--no-same-permissions"], at: archiveDirectory)
            let unpacked = try Data(contentsOf: out.appendingPathComponent("Türkçe boşluk.txt")); assert(unpacked == contents)
        }
        print("PASS: copy, collision preservation, recursive copy, symlinks, self-transfer rejection, cancellation, rename, duplicate rejection, safe archive paths, move, sync with backup, partial-copy cleanup, settings defaults/persistence/reset, ZIP and 7z round trips")
    }
}
