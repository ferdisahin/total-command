// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class SyncTests {
    static func run() {
        testIdenticalFolders()
        testDirectionalSync()
        testAsymmetricSync()
        testByContentHashComparison()
        testExecution()
        print("PASS: Two-way sync engine, directional detection, asymmetric deletion, SHA-256 content check, and sync execution")
    }

    private static func testIdenticalFolders() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("sync-test-\(UUID().uuidString)")
        let left = tempDir.appendingPathComponent("left")
        let right = tempDir.appendingPathComponent("right")
        try! fm.createDirectory(at: left, withIntermediateDirectories: true)
        try! fm.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try! Data("Same content".utf8).write(to: left.appendingPathComponent("doc.txt"))
        try! Data("Same content".utf8).write(to: right.appendingPathComponent("doc.txt"))

        var opt = SyncOptions()
        opt.ignoreDate = true
        let items = try! SyncEngine.compareDirectories(left: left, right: right, options: opt)
        assert(items.count == 1)
        assert(items[0].direction == .equal, "Expected equal direction")
    }

    private static func testDirectionalSync() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("sync-dir-\(UUID().uuidString)")
        let left = tempDir.appendingPathComponent("left")
        let right = tempDir.appendingPathComponent("right")
        try! fm.createDirectory(at: left, withIntermediateDirectories: true)
        try! fm.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try! Data("Left only".utf8).write(to: left.appendingPathComponent("only_left.txt"))
        try! Data("Right only".utf8).write(to: right.appendingPathComponent("only_right.txt"))

        let opt = SyncOptions()
        let items = try! SyncEngine.compareDirectories(left: left, right: right, options: opt)
        assert(items.count == 2)

        let leftItem = items.first { $0.relativePath == "only_left.txt" }
        assert(leftItem?.direction == .copyRight)

        let rightItem = items.first { $0.relativePath == "only_right.txt" }
        assert(rightItem?.direction == .copyLeft)
    }

    private static func testAsymmetricSync() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("sync-asym-\(UUID().uuidString)")
        let left = tempDir.appendingPathComponent("left")
        let right = tempDir.appendingPathComponent("right")
        try! fm.createDirectory(at: left, withIntermediateDirectories: true)
        try! fm.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try! Data("Right file".utf8).write(to: right.appendingPathComponent("extra.txt"))

        var opt = SyncOptions()
        opt.asymmetric = true
        let items = try! SyncEngine.compareDirectories(left: left, right: right, options: opt)
        assert(items.count == 1)
        assert(items[0].direction == .deleteRight, "In asymmetric mode, right file should be marked deleteRight")
    }

    private static func testByContentHashComparison() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("sync-hash-\(UUID().uuidString)")
        let left = tempDir.appendingPathComponent("left")
        let right = tempDir.appendingPathComponent("right")
        try! fm.createDirectory(at: left, withIntermediateDirectories: true)
        try! fm.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Two files with identical size (10 bytes) but different bytes
        try! Data("1234567890".utf8).write(to: left.appendingPathComponent("data.bin"))
        try! Data("0987654321".utf8).write(to: right.appendingPathComponent("data.bin"))

        var opt = SyncOptions()
        opt.byContent = true
        let items = try! SyncEngine.compareDirectories(left: left, right: right, options: opt)
        assert(items.count == 1)
        assert(items[0].direction != .equal, "Files with different hashes must not be equal")
    }

    private static func testExecution() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("sync-exec-\(UUID().uuidString)")
        let left = tempDir.appendingPathComponent("left")
        let right = tempDir.appendingPathComponent("right")
        try! fm.createDirectory(at: left, withIntermediateDirectories: true)
        try! fm.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try! Data("New left".utf8).write(to: left.appendingPathComponent("a.txt"))
        try! Data("New right".utf8).write(to: right.appendingPathComponent("b.txt"))

        let opt = SyncOptions()
        let items = try! SyncEngine.compareDirectories(left: left, right: right, options: opt)
        let control = JobState()
        try! SyncEngine.executeSync(items: items, control: control, progress: { _, _, _ in })

        assert(fm.fileExists(atPath: right.appendingPathComponent("a.txt").path), "a.txt should be copied to right")
        assert(fm.fileExists(atPath: left.appendingPathComponent("b.txt").path), "b.txt should be copied to left")
    }
}
