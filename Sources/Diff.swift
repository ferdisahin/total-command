// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation
import CryptoKit

enum DiffLineType: Equatable {
    case same
    case added
    case deleted
    case modified
    case empty
}

struct AlignedDiffRow: Equatable {
    let index: Int
    let leftLineNum: Int?
    let leftContent: String?
    let leftType: DiffLineType
    let rightLineNum: Int?
    let rightContent: String?
    let rightType: DiffLineType

    var isDifference: Bool {
        leftType != .same || rightType != .same
    }
}

struct BinaryDiffResult: Equatable {
    let isIdentical: Bool
    let leftSize: Int64
    let rightSize: Int64
    let leftSHA256: String
    let rightSHA256: String
    let firstDifferenceOffset: Int64?
    let leftByte: UInt8?
    let rightByte: UInt8?
}

enum DiffResult {
    case binary(BinaryDiffResult)
    case text(rows: [AlignedDiffRow], diffCount: Int, addedCount: Int, deletedCount: Int, modifiedCount: Int)
}

enum DiffEditOp: Equatable {
    case same(String)
    case delete(String)
    case insert(String)
}

final class DiffEngine {
    static func isBinaryFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else { return false }
        if data.contains(0x00) { return true }
        return String(data: data, encoding: .utf8) == nil
    }

    static func compare(leftURL: URL, rightURL: URL) throws -> DiffResult {
        let leftIsBin = isBinaryFile(leftURL)
        let rightIsBin = isBinaryFile(rightURL)

        if leftIsBin || rightIsBin {
            return .binary(compareBinary(leftURL: leftURL, rightURL: rightURL))
        }

        guard let leftText = try? String(contentsOf: leftURL, encoding: .utf8),
              let rightText = try? String(contentsOf: rightURL, encoding: .utf8) else {
            return .binary(compareBinary(leftURL: leftURL, rightURL: rightURL))
        }

        let result = compareText(leftText: leftText, rightText: rightText)
        return .text(rows: result.rows, diffCount: result.diffCount, addedCount: result.addedCount, deletedCount: result.deletedCount, modifiedCount: result.modifiedCount)
    }

    static func compareBinary(leftURL: URL, rightURL: URL) -> BinaryDiffResult {
        let leftData = (try? Data(contentsOf: leftURL, options: .alwaysMapped)) ?? Data()
        let rightData = (try? Data(contentsOf: rightURL, options: .alwaysMapped)) ?? Data()

        let leftHash = SHA256.hash(data: leftData).map { String(format: "%02x", $0) }.joined()
        let rightHash = SHA256.hash(data: rightData).map { String(format: "%02x", $0) }.joined()

        let isIdentical = leftData == rightData
        var firstDiffOffset: Int64?
        var leftByte: UInt8?
        var rightByte: UInt8?

        if !isIdentical {
            let minLen = min(leftData.count, rightData.count)
            for i in 0..<minLen {
                if leftData[i] != rightData[i] {
                    firstDiffOffset = Int64(i)
                    leftByte = leftData[i]
                    rightByte = rightData[i]
                    break
                }
            }
            if firstDiffOffset == nil && leftData.count != rightData.count {
                firstDiffOffset = Int64(minLen)
                leftByte = leftData.count > minLen ? leftData[minLen] : nil
                rightByte = rightData.count > minLen ? rightData[minLen] : nil
            }
        }

        return BinaryDiffResult(
            isIdentical: isIdentical,
            leftSize: Int64(leftData.count),
            rightSize: Int64(rightData.count),
            leftSHA256: leftHash,
            rightSHA256: rightHash,
            firstDifferenceOffset: firstDiffOffset,
            leftByte: leftByte,
            rightByte: rightByte
        )
    }

    static func compareText(leftText: String, rightText: String) -> (rows: [AlignedDiffRow], diffCount: Int, addedCount: Int, deletedCount: Int, modifiedCount: Int) {
        let leftLines = leftText.isEmpty ? [] : leftText.components(separatedBy: "\n")
        let rightLines = rightText.isEmpty ? [] : rightText.components(separatedBy: "\n")

        if leftLines == rightLines {
            var rows: [AlignedDiffRow] = []
            for (idx, line) in leftLines.enumerated() {
                rows.append(AlignedDiffRow(index: idx, leftLineNum: idx + 1, leftContent: line, leftType: .same, rightLineNum: idx + 1, rightContent: line, rightType: .same))
            }
            return (rows, 0, 0, 0, 0)
        }

        let ops = computeMyersDiff(a: leftLines, b: rightLines)
        return alignDiff(ops: ops)
    }

    static func computeMyersDiff(a: [String], b: [String]) -> [DiffEditOp] {
        let n = a.count
        let m = b.count
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }

        let maxD = n + m
        var v = [Int: Int]()
        v[1] = 0
        var trace = [[Int: Int]]()

        outer: for d in 0...maxD {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && (v[k - 1] ?? 0) < (v[k + 1] ?? 0)) {
                    x = v[k + 1] ?? 0
                } else {
                    x = (v[k - 1] ?? 0) + 1
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[k] = x
                if x >= n && y >= m {
                    break outer
                }
            }
        }

        var ops: [DiffEditOp] = []
        var x = n
        var y = m
        for d in (0..<trace.count).reversed() {
            let vPrev = trace[d]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && (vPrev[k - 1] ?? 0) < (vPrev[k + 1] ?? 0)) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }
            let prevX = vPrev[prevK] ?? 0
            let prevY = prevX - prevK

            while x > prevX && y > prevY {
                x -= 1
                y -= 1
                ops.append(.same(a[x]))
            }
            if d > 0 {
                if x == prevX {
                    y -= 1
                    ops.append(.insert(b[y]))
                } else if y == prevY {
                    x -= 1
                    ops.append(.delete(a[x]))
                }
            }
        }
        return ops.reversed()
    }

    static func alignDiff(ops: [DiffEditOp]) -> (rows: [AlignedDiffRow], diffCount: Int, addedCount: Int, deletedCount: Int, modifiedCount: Int) {
        var rows: [AlignedDiffRow] = []
        var leftLine = 1
        var rightLine = 1
        var diffCount = 0
        var addedCount = 0
        var deletedCount = 0
        var modifiedCount = 0

        var i = 0
        while i < ops.count {
            switch ops[i] {
            case .same(let str):
                rows.append(AlignedDiffRow(
                    index: rows.count,
                    leftLineNum: leftLine,
                    leftContent: str,
                    leftType: .same,
                    rightLineNum: rightLine,
                    rightContent: str,
                    rightType: .same
                ))
                leftLine += 1
                rightLine += 1
                i += 1

            case .delete, .insert:
                // Collect contiguous deletes and inserts
                var deletes: [String] = []
                var inserts: [String] = []

                while i < ops.count {
                    if case .delete(let d) = ops[i] {
                        deletes.append(d)
                        i += 1
                    } else if case .insert(let ins) = ops[i] {
                        inserts.append(ins)
                        i += 1
                    } else {
                        break
                    }
                }

                diffCount += 1
                let maxLen = max(deletes.count, inserts.count)
                for step in 0..<maxLen {
                    let hasDel = step < deletes.count
                    let hasIns = step < inserts.count

                    let lNum: Int? = hasDel ? leftLine : nil
                    let lText: String? = hasDel ? deletes[step] : nil
                    let rNum: Int? = hasIns ? rightLine : nil
                    let rText: String? = hasIns ? inserts[step] : nil

                    let lType: DiffLineType
                    let rType: DiffLineType

                    if hasDel && hasIns {
                        lType = .modified
                        rType = .modified
                        modifiedCount += 1
                    } else if hasDel {
                        lType = .deleted
                        rType = .empty
                        deletedCount += 1
                    } else {
                        lType = .empty
                        rType = .added
                        addedCount += 1
                    }

                    rows.append(AlignedDiffRow(
                        index: rows.count,
                        leftLineNum: lNum,
                        leftContent: lText,
                        leftType: lType,
                        rightLineNum: rNum,
                        rightContent: rText,
                        rightType: rType
                    ))

                    if hasDel { leftLine += 1 }
                    if hasIns { rightLine += 1 }
                }
            }
        }

        return (rows, diffCount, addedCount, deletedCount, modifiedCount)
    }
}
