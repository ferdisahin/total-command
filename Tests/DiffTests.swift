// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class DiffTests {
    static func run() {
        testIdenticalText()
        testSimpleModifications()
        testAdditionsAndDeletions()
        testEmptyFiles()
        testBinaryComparison()
        print("PASS: Myers diff algorithm, text alignment, modifications, deletions, and binary offset comparison")
    }

    private static func testIdenticalText() {
        let text = "Line 1\nLine 2\nLine 3"
        let result = DiffEngine.compareText(leftText: text, rightText: text)
        assert(result.diffCount == 0, "Identical text should have 0 differences")
        assert(result.addedCount == 0 && result.deletedCount == 0 && result.modifiedCount == 0)
        assert(result.rows.count == 3, "Rows count should match lines count")
        assert(result.rows.allSatisfy { $0.leftType == .same && $0.rightType == .same })
    }

    private static func testSimpleModifications() {
        let left = "function test() {\n  return 1;\n}"
        let right = "function test() {\n  return 2;\n}"
        let result = DiffEngine.compareText(leftText: left, rightText: right)
        assert(result.diffCount == 1, "Expected 1 diff region")
        assert(result.modifiedCount == 1, "Expected 1 modified line")
        assert(result.rows.count == 3, "Expected 3 aligned rows")
        assert(result.rows[1].leftType == .modified && result.rows[1].rightType == .modified)
        assert(result.rows[1].leftContent == "  return 1;")
        assert(result.rows[1].rightContent == "  return 2;")
    }

    private static func testAdditionsAndDeletions() {
        let left = "Alpha\nBeta\nGamma"
        let right = "Alpha\nGamma\nDelta"
        let result = DiffEngine.compareText(leftText: left, rightText: right)
        assert(result.diffCount >= 1, "Expected diffs")
        assert(result.deletedCount == 1, "Expected 1 deleted line (Beta)")
        assert(result.addedCount == 1, "Expected 1 added line (Delta)")
    }

    private static func testEmptyFiles() {
        let empty = ""
        let nonEmpty = "Hello World"
        let res1 = DiffEngine.compareText(leftText: empty, rightText: empty)
        assert(res1.diffCount == 0)

        let res2 = DiffEngine.compareText(leftText: empty, rightText: nonEmpty)
        assert(res2.addedCount == 1 && res2.diffCount == 1)

        let res3 = DiffEngine.compareText(leftText: nonEmpty, rightText: empty)
        assert(res3.deletedCount == 1 && res3.diffCount == 1)
    }

    private static func testBinaryComparison() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("diff-test-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("file1.bin")
        let file2 = tempDir.appendingPathComponent("file2.bin")
        let file3 = tempDir.appendingPathComponent("file3.bin")

        let data1 = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        let data2 = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        let data3 = Data([0x00, 0x01, 0x02, 0x04, 0xFF])

        try! data1.write(to: file1)
        try! data2.write(to: file2)
        try! data3.write(to: file3)

        assert(DiffEngine.isBinaryFile(file1) == true, "file1 should be detected as binary")

        let binSame = DiffEngine.compareBinary(leftURL: file1, rightURL: file2)
        assert(binSame.isIdentical == true, "file1 and file2 should be identical")
        assert(binSame.firstDifferenceOffset == nil)

        let binDiff = DiffEngine.compareBinary(leftURL: file1, rightURL: file3)
        assert(binDiff.isIdentical == false, "file1 and file3 should differ")
        assert(binDiff.firstDifferenceOffset == 3, "First diff offset should be at index 3")
        assert(binDiff.leftByte == 0x03)
        assert(binDiff.rightByte == 0x04)
    }
}
