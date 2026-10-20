// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

final class RemoteTests {
    static func run() {
        testProtocolDefaults()
        testSiteSerialization()
        testUnixListingParser()
        testWindowsListingOrEdgeCases()
        print("PASS: remote protocol defaults, site store serialization, unix ls parser and space-separated path resolution")
    }

    private static func testProtocolDefaults() {
        assert(RemoteProtocol.sftp.defaultPort == 22, "SFTP default port should be 22")
        assert(RemoteProtocol.ftp.defaultPort == 21, "FTP default port should be 21")
        assert(RemoteProtocol.ftps.defaultPort == 21, "FTPS default port should be 21")
        assert(RemoteProtocol.sftp.scheme == "sftp", "SFTP scheme should be sftp")
        assert(RemoteProtocol.ftp.scheme == "ftp", "FTP scheme should be ftp")
        assert(RemoteProtocol.ftps.scheme == "ftps", "FTPS scheme should be ftps")
    }

    private static func testSiteSerialization() {
        let site = RemoteSite(name: "Turhost Prod", protocolType: .sftp, host: "prod.turhost.com", port: 2222, username: "ferdi", password: "secretPassword", privateKeyPath: "~/.ssh/id_ed25519", remotePath: "/var/www/html")

        assert(site.displayURLString == "sftp://ferdi@prod.turhost.com:2222/var/www/html", "Unexpected display URL string: \(site.displayURLString)")

        let data = try! JSONEncoder().encode([site])
        let decoded = try! JSONDecoder().decode([RemoteSite].self, from: data)
        assert(decoded.count == 1, "Decoded sites count should be 1")
        assert(decoded[0].name == "Turhost Prod", "Decoded site name mismatch")
        assert(decoded[0].port == 2222, "Decoded site port mismatch")
        assert(decoded[0].protocolType == .sftp, "Decoded site protocol mismatch")
    }

    private static func testUnixListingParser() {
        let sampleOutput = """
        total 48
        drwxr-xr-x   5 root  wheel   160 Oct 19 14:30 .
        drwxr-xr-x+ 45 root  wheel  1440 Oct 19 11:20 ..
        drwxr-xr-x   3 user  staff    96 Oct 19 12:00 public_html
        -rw-r--r--   1 user  staff  2048 Oct 18  2025 index.php
        -rw-r--r--   1 user  staff 1048576 Oct 19 14:15 backup archive 2026.tar.gz
        lrwxrwxrwx   1 user  staff    11 Oct 19 14:20 current -> public_html
        """

        let entries = RemoteParser.parseUnixListing(sampleOutput, basePath: "/var/www")

        // Should ignore "." and ".."
        assert(entries.count == 4, "Expected 4 entries, got \(entries.count)")

        // Check directory
        let dir = entries.first(where: { $0.name == "public_html" })
        assert(dir != nil, "public_html not found")
        assert(dir!.isDirectory == true, "public_html should be a directory")
        assert(dir!.path == "/var/www/public_html", "Path should be /var/www/public_html")

        // Check file
        let php = entries.first(where: { $0.name == "index.php" })
        assert(php != nil, "index.php not found")
        assert(php!.isDirectory == false, "index.php should not be a directory")
        assert(php!.size == 2048, "index.php size should be 2048 bytes")
        assert(php!.ext == "php", "index.php extension should be php")

        // Check file with spaces in name
        let spaceFile = entries.first(where: { $0.name == "backup archive 2026.tar.gz" })
        assert(spaceFile != nil, "backup archive 2026.tar.gz not found")
        assert(spaceFile!.size == 1048576, "backup archive size mismatch")
        assert(spaceFile!.path == "/var/www/backup archive 2026.tar.gz", "Path with spaces mismatch")

        // Check symlink
        let link = entries.first(where: { $0.name == "current" })
        assert(link != nil, "current symlink not found")
        assert(link!.name == "current", "Symlink arrow should be stripped from name")
    }

    private static func testWindowsListingOrEdgeCases() {
        let emptyOutput = ""
        let emptyEntries = RemoteParser.parseUnixListing(emptyOutput, basePath: "/")
        assert(emptyEntries.isEmpty, "Empty output should produce no entries")

        let headerOnly = "total 0\n"
        let headerEntries = RemoteParser.parseUnixListing(headerOnly, basePath: "/")
        assert(headerEntries.isEmpty, "Header only output should produce no entries")
    }
}
