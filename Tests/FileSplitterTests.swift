// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class FileSplitterTests {
    static func run() {
        testCRC32Calculation()
        testSplitAndCombineCycle()
        testCRCMismatchDetection()
        print("PASS: CRC32 calculations, file splitting, chunk detection, combining, and CRC mismatch guard")
    }

    private static func testCRC32Calculation() {
        let data = Data("123456789".utf8)
        let crc = CRC32.calculate(data: data)
        assert(crc == "CBF43926", "Expected CBF43926, got \(crc)")
    }

    private static func testSplitAndCombineCycle() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("split-test-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let originalFile = tempDir.appendingPathComponent("document.bin")
        let outSplitDir = tempDir.appendingPathComponent("parts")
        let outCombineDir = tempDir.appendingPathComponent("combined")
        try! fm.createDirectory(at: outSplitDir, withIntermediateDirectories: true)
        try! fm.createDirectory(at: outCombineDir, withIntermediateDirectories: true)

        // Create 250 KB file
        var sampleBytes = [UInt8](repeating: 0, count: 250 * 1024)
        for i in 0..<sampleBytes.count {
            sampleBytes[i] = UInt8(i % 256)
        }
        let sampleData = Data(sampleBytes)
        try! sampleData.write(to: originalFile)

        // Split into 64 KB chunks (should produce 4 chunks: 64k, 64k, 64k, 58k)
        let chunkSize: Int64 = 64 * 1024
        let control = JobState()
        let createdParts = try! FileSplitter.split(source: originalFile, destinationDir: outSplitDir, chunkSize: chunkSize, generateCRC: true, control: control, progress: { _, _, _ in })

        assert(createdParts.count == 5, "Expected 4 parts + 1 crc file, got \(createdParts.count)")
        let part1 = outSplitDir.appendingPathComponent("document.bin.001")
        assert(fm.fileExists(atPath: part1.path), "document.bin.001 should exist")
        assert(fm.fileExists(atPath: outSplitDir.appendingPathComponent("document.bin.crc").path), "document.bin.crc should exist")

        // Detect parts
        let detected = FileSplitter.detectParts(firstPart: part1)
        assert(detected.parts.count == 4, "Expected 4 detected parts")
        assert(detected.originalName == "document.bin")
        assert(detected.crcURL != nil, "CRC file should be detected")

        // Combine
        let combinedURL = try! FileSplitter.combine(parts: detected.parts, originalName: detected.originalName, destinationDir: outCombineDir, crcURL: detected.crcURL, verifyCRC: true, control: control, progress: { _, _, _ in })

        let combinedData = try! Data(contentsOf: combinedURL)
        assert(combinedData == sampleData, "Combined data must match original data exactly")
    }

    private static func testCRCMismatchDetection() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("crc-mismatch-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let originalFile = tempDir.appendingPathComponent("test.txt")
        let splitDir = tempDir.appendingPathComponent("split")
        let combineDir = tempDir.appendingPathComponent("combined")
        try! fm.createDirectory(at: splitDir, withIntermediateDirectories: true)
        try! fm.createDirectory(at: combineDir, withIntermediateDirectories: true)

        let content = Data("Some important content that will be tampered".utf8)
        try! content.write(to: originalFile)

        let control = JobState()
        _ = try! FileSplitter.split(source: originalFile, destinationDir: splitDir, chunkSize: 10, generateCRC: true, control: control, progress: { _, _, _ in })

        // Tamper with first chunk
        let part1 = splitDir.appendingPathComponent("test.txt.001")
        try! Data("TAMPERED!!".utf8).write(to: part1)

        let detected = FileSplitter.detectParts(firstPart: part1)

        var didFail = false
        do {
            _ = try FileSplitter.combine(parts: detected.parts, originalName: detected.originalName, destinationDir: combineDir, crcURL: detected.crcURL, verifyCRC: true, control: control, progress: { _, _, _ in })
        } catch {
            didFail = true
        }
        assert(didFail, "Combining tampered chunks with CRC check should throw error")
    }
}
