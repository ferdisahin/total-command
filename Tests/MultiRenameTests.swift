// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class MultiRenameTests {
    static func run() {
        testBasicPatterns()
        testAdvancedCounter()
        testSearchAndReplace()
        testRegexReplace()
        testCaseConversions()
        testDuplicateDetection()
        testDatePatterns()
        print("PASS: Multi-rename templates, substring slices, regex search/replace, case conversions, and duplicate collision guard")
    }

    private static func testDatePatterns() {
        let urls = [URL(fileURLWithPath: "/tmp/alpha.txt")]
        var opt = MultiRenameOptions()
        opt.namePattern = "[N]-[C]-[YMD]"
        opt.extPattern = "[E]"

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items.count == 1)
        assert(!items[0].newName.contains("[YMD]"), "Date tag [YMD] should be expanded")
        assert(items[0].newName.hasPrefix("alpha-1-20"), "Expected alpha-1-20... got \(items[0].newName)")
    }

    private static func testBasicPatterns() {
        let urls = [
            URL(fileURLWithPath: "/tmp/photo_vacation.jpg"),
            URL(fileURLWithPath: "/tmp/report.pdf")
        ]
        var opt = MultiRenameOptions()
        opt.namePattern = "[N]_new"
        opt.extPattern = "[E]"

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items.count == 2)
        assert(items[0].newName == "photo_vacation_new.jpg")
        assert(items[1].newName == "report_new.pdf")
    }

    private static func testAdvancedCounter() {
        let urls = [
            URL(fileURLWithPath: "/tmp/docA.txt"),
            URL(fileURLWithPath: "/tmp/docB.txt"),
            URL(fileURLWithPath: "/tmp/docC.txt")
        ]
        var opt = MultiRenameOptions()
        opt.namePattern = "item_[C]"
        opt.extPattern = "[E]"
        opt.counterStart = 10
        opt.counterStep = 5
        opt.counterDigits = 3

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items[0].newName == "item_010.txt")
        assert(items[1].newName == "item_015.txt")
        assert(items[2].newName == "item_020.txt")
    }

    private static func testSearchAndReplace() {
        let urls = [URL(fileURLWithPath: "/tmp/IMG_2026_OLD.PNG")]
        var opt = MultiRenameOptions()
        opt.namePattern = "[N]"
        opt.extPattern = "[E]"
        opt.search = "OLD"
        opt.replace = "FINAL"

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items[0].newName == "IMG_2026_FINAL.PNG")
    }

    private static func testRegexReplace() {
        let urls = [URL(fileURLWithPath: "/tmp/track-01-intro.mp3")]
        var opt = MultiRenameOptions()
        opt.namePattern = "[N]"
        opt.extPattern = "[E]"
        opt.useRegex = true
        opt.search = #"track-([0-9]+)-(.*)"#
        opt.replace = "S01E$1 - $2"

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items[0].newName == "S01E01 - intro.mp3")
    }

    private static func testCaseConversions() {
        let urls = [URL(fileURLWithPath: "/tmp/hello world.txt")]
        var opt = MultiRenameOptions()
        opt.namePattern = "[N]"
        opt.extPattern = "[E]"

        opt.caseConversion = .uppercase
        assert(MultiRenameEngine.generateNames(urls: urls, options: opt)[0].newName == "HELLO WORLD.TXT")

        opt.caseConversion = .titleCase
        assert(MultiRenameEngine.generateNames(urls: urls, options: opt)[0].newName == "Hello World.Txt")
    }

    private static func testDuplicateDetection() {
        let urls = [
            URL(fileURLWithPath: "/tmp/file1.txt"),
            URL(fileURLWithPath: "/tmp/file2.txt")
        ]
        var opt = MultiRenameOptions()
        opt.namePattern = "same_name"
        opt.extPattern = "txt"

        let items = MultiRenameEngine.generateNames(urls: urls, options: opt)
        assert(items[0].error != nil && items[1].error != nil, "Duplicate target names should trigger an error")
    }
}
