// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class ChecksumTests {
    static func run() {
        testStandardHashVectors()
        testChecksumGenerationAndParsing()
        testVerificationStatus()
        testSFVFormat()
        print("PASS: Checksum engine, RFC vectors (MD5, SHA1, SHA256, SHA512, CRC32), file generation, SFV format, and integrity verification")
    }

    private static func testStandardHashVectors() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("checksum-vec-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let emptyFile = tempDir.appendingPathComponent("empty.txt")
        try! Data().write(to: emptyFile)

        let foxFile = tempDir.appendingPathComponent("fox.txt")
        let foxData = Data("The quick brown fox jumps over the lazy dog".utf8)
        try! foxData.write(to: foxFile)

        // Empty file tests
        assert(try! ChecksumEngine.calculateHash(url: emptyFile, algorithm: .md5) == "d41d8cd98f00b204e9800998ecf8427e")
        assert(try! ChecksumEngine.calculateHash(url: emptyFile, algorithm: .sha1) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        assert(try! ChecksumEngine.calculateHash(url: emptyFile, algorithm: .sha256) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        assert(try! ChecksumEngine.calculateHash(url: emptyFile, algorithm: .crc32) == "00000000")

        // "The quick brown fox jumps over the lazy dog" tests
        assert(try! ChecksumEngine.calculateHash(url: foxFile, algorithm: .md5) == "9e107d9d372bb6826bd81d3542a419d6")
        assert(try! ChecksumEngine.calculateHash(url: foxFile, algorithm: .sha1) == "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
        assert(try! ChecksumEngine.calculateHash(url: foxFile, algorithm: .sha256) == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
        assert(try! ChecksumEngine.calculateHash(url: foxFile, algorithm: .crc32) == "414fa339")
    }

    private static func testChecksumGenerationAndParsing() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("checksum-gen-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("fileA.txt")
        let fileB = tempDir.appendingPathComponent("fileB.txt")
        try! Data("Hello Total Command".utf8).write(to: fileA)
        try! Data("Second file content".utf8).write(to: fileB)

        let content = try! ChecksumEngine.generateChecksumContent(files: [fileA, fileB], baseDir: tempDir, algorithm: .sha256)
        let chkURL = tempDir.appendingPathComponent("checksums.sha256")
        try! content.write(to: chkURL, atomically: true, encoding: .utf8)

        let (algo, records) = try! ChecksumEngine.parseChecksumFile(url: chkURL)
        assert(algo == .sha256, "Expected SHA-256 algorithm")
        assert(records.count == 2, "Expected 2 records")
        assert(records[0].relativePath == "fileA.txt")
        assert(records[1].relativePath == "fileB.txt")
    }

    private static func testVerificationStatus() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("checksum-ver-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let fileGood = tempDir.appendingPathComponent("good.txt")
        let fileBad = tempDir.appendingPathComponent("bad.txt")
        let fileMissing = tempDir.appendingPathComponent("missing.txt")

        try! Data("Original content".utf8).write(to: fileGood)
        try! Data("Initial bad content".utf8).write(to: fileBad)
        try! Data("Will be deleted".utf8).write(to: fileMissing)

        let content = try! ChecksumEngine.generateChecksumContent(files: [fileGood, fileBad, fileMissing], baseDir: tempDir, algorithm: .sha256)
        let chkURL = tempDir.appendingPathComponent("test.sha256")
        try! content.write(to: chkURL, atomically: true, encoding: .utf8)

        // Modify bad.txt and delete missing.txt
        try! Data("Tampered content".utf8).write(to: fileBad)
        try! fm.removeItem(at: fileMissing)

        let (algo, records) = try! ChecksumEngine.parseChecksumFile(url: chkURL)
        let results = try! ChecksumEngine.verifyRecords(records: records, baseDir: tempDir, algorithm: algo, control: JobState(), progress: { _, _, _ in })

        assert(results.count == 3)
        assert(results[0].status == .ok, "good.txt must be ok")
        if case .mismatch = results[1].status {
            // expected
        } else {
            assertionFailure("bad.txt must be mismatch")
        }
        assert(results[2].status == .missing, "missing.txt must be missing")
    }

    private static func testSFVFormat() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("checksum-sfv-\(UUID().uuidString)")
        try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("sample.bin")
        try! Data("SFV test data".utf8).write(to: file1)

        let sfvContent = try! ChecksumEngine.generateChecksumContent(files: [file1], baseDir: tempDir, algorithm: .crc32)
        let sfvURL = tempDir.appendingPathComponent("sample.sfv")
        try! sfvContent.write(to: sfvURL, atomically: true, encoding: .utf8)

        let (algo, records) = try! ChecksumEngine.parseChecksumFile(url: sfvURL)
        assert(algo == .crc32, "Expected CRC32 algorithm for .sfv")
        assert(records.count == 1)

        let results = try! ChecksumEngine.verifyRecords(records: records, baseDir: tempDir, algorithm: algo, control: JobState(), progress: { _, _, _ in })
        assert(results[0].status == .ok, "sample.bin must be verified ok via SFV")
    }
}
