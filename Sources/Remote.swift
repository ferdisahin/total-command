// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation
import Cocoa

enum RemoteProtocol: String, Codable, CaseIterable {
    case sftp = "SFTP"
    case ftp = "FTP"
    case ftps = "FTPS"

    var defaultPort: Int {
        switch self {
        case .sftp: return 22
        case .ftp, .ftps: return 21
        }
    }

    // FTPS uses explicit TLS on port 21; curl ftps:// would imply immediate TLS.
    var curlScheme: String { self == .ftps ? "ftp" : scheme }

    var scheme: String {
        switch self {
        case .sftp: return "sftp"
        case .ftp: return "ftp"
        case .ftps: return "ftps"
        }
    }
}

struct RemoteSite: Codable, Equatable {
    var id = UUID()
    var name: String
    var protocolType: RemoteProtocol = .sftp
    var host: String
    var port: Int = 22
    var username: String = ""
    var password: String = ""
    var privateKeyPath: String = ""
    var remotePath: String = "/"

    var displayURLString: String {
        let userPart = username.isEmpty ? "" : "\(username)@"
        let portPart = port == protocolType.defaultPort ? "" : ":\(port)"
        let pathPart = remotePath.hasPrefix("/") ? remotePath : "/\(remotePath)"
        return "\(protocolType.scheme)://\(userPart)\(host)\(portPart)\(pathPart)"
    }
}

struct RemoteEntry: Equatable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let date: Date
    let permissions: String
    var isParent: Bool = false

    var ext: String {
        if isDirectory || isParent { return "" }
        let comps = name.split(separator: ".")
        return comps.count > 1 ? String(comps.last!) : ""
    }

    func toAppEntry(baseURL: URL) -> Entry {
        let fileURL = baseURL.appendingPathComponent(name)
        return Entry(url: fileURL, directory: isDirectory, size: size, date: date, isParent: isParent)
    }
}

final class RemoteParser {
    // Standard Unix `ls -la` month tokens in English
    private static let monthMap: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
        "oca": 1, "şub": 2, "nis": 4, "haz": 6,
        "tem": 7, "ağu": 8, "eyl": 9, "eki": 10, "kas": 11, "ara": 12
    ]

    static func parseUnixListing(_ output: String, basePath: String) -> [RemoteEntry] {
        var results: [RemoteEntry] = []
        let lines = output.components(separatedBy: .newlines)
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total ") || trimmed.hasPrefix("Toplam ") { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8 else { continue }

            let perm = String(parts[0])
            guard perm.count >= 9 else { continue }
            let isDir = perm.first == "d"

            // Find the month/date token index
            var dateIndex = -1
            for i in 1..<(parts.count - 3) {
                let token = String(parts[i]).lowercased()
                if monthMap[token] != nil || (token.contains("-") && token.count >= 8) {
                    dateIndex = i
                    break
                }
            }
            guard dateIndex >= 4, parts.count > dateIndex + 3 else { continue }

            let fileSize = Int64(parts[dateIndex - 1]) ?? 0
            let monthStr = String(parts[dateIndex]).lowercased()
            let dayStr = String(parts[dateIndex + 1])
            let timeOrYear = String(parts[dateIndex + 2])

            // Name is everything after timeOrYear
            let nameTokens = parts[(dateIndex + 3)...]
            var rawName = nameTokens.joined(separator: " ")
            if let arrowIndex = rawName.range(of: " -> ") {
                rawName = String(rawName[..<arrowIndex.lowerBound])
            }

            if rawName == "." || rawName == ".." { continue }

            // Date parsing
            var date = Date()
            if let month = monthMap[monthStr] ?? Int(monthStr), let day = Int(dayStr) {
                var components = DateComponents()
                components.month = month
                components.day = day
                if timeOrYear.contains(":") {
                    let timeParts = timeOrYear.split(separator: ":")
                    components.year = currentYear
                    components.hour = Int(timeParts.first ?? "0")
                    components.minute = Int(timeParts.last ?? "0")
                } else if let year = Int(timeOrYear) {
                    components.year = year
                    components.hour = 12
                    components.minute = 0
                }
                date = calendar.date(from: components) ?? Date()
            }

            let fullPath = basePath.hasSuffix("/") ? "\(basePath)\(rawName)" : "\(basePath)/\(rawName)"
            results.append(RemoteEntry(name: rawName, path: fullPath, isDirectory: isDir, size: fileSize, date: date, permissions: perm))
        }

        return results
    }
}

final class RemoteSession: @unchecked Sendable {
    let site: RemoteSite
    var currentPath: String
    private let queue = DispatchQueue(label: "com.totalcommand.remote", qos: .userInitiated)

    init(site: RemoteSite) {
        self.site = site
        self.currentPath = site.remotePath.isEmpty ? "/" : site.remotePath
    }

    var displayURLString: String {
        let scheme = site.protocolType.scheme
        let userPart = site.username.isEmpty ? "" : "\(site.username)@"
        let portPart = site.port == site.protocolType.defaultPort ? "" : ":\(site.port)"
        let pathPart = currentPath.hasPrefix("/") ? currentPath : "/\(currentPath)"
        return "\(scheme)://\(userPart)\(site.host)\(portPart)\(pathPart)"
    }

    var virtualURL: URL {
        let scheme = site.protocolType.scheme
        let user = site.username.isEmpty ? "anonymous" : site.username
        let portPart = ":\(site.port)"
        let cleanPath = currentPath.hasPrefix("/") ? currentPath : "/\(currentPath)"
        let full = "\(scheme)://\(user)@\(site.host)\(portPart)\(cleanPath)"
        return URL(string: full) ?? URL(fileURLWithPath: currentPath)
    }

    func listDirectory(path: String, completion: @escaping (Result<[RemoteEntry], Error>) -> Void) {
        queue.async {
            do {
                let entries: [RemoteEntry]
                switch self.site.protocolType {
                case .sftp:
                    entries = try self.listSFTP(path: path)
                case .ftp, .ftps:
                    entries = try self.listFTP(path: path)
                }
                DispatchQueue.main.async { completion(.success(entries)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func download(remotePath: String, to localURL: URL, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        switch site.protocolType {
        case .sftp:
            try downloadSFTP(remotePath: remotePath, to: localURL, control: control, progress: progress)
        case .ftp, .ftps:
            try downloadFTP(remotePath: remotePath, to: localURL, control: control, progress: progress)
        }
    }

    func upload(localURL: URL, to remoteDir: String, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        switch site.protocolType {
        case .sftp:
            try uploadSFTP(localURL: localURL, to: remoteDir, control: control, progress: progress)
        case .ftp, .ftps:
            try uploadFTP(localURL: localURL, to: remoteDir, control: control, progress: progress)
        }
    }

    func makeDirectory(path: String) throws {
        switch site.protocolType {
        case .sftp:
            _ = try runSFTP(commands: ["mkdir \"\(path)\""])
        case .ftp, .ftps:
            let cmd = "MKD \(path)"
            _ = try runCurlFTP(quoteCommands: [cmd], path: path)
        }
    }

    func remove(path: String, isDirectory: Bool) throws {
        switch site.protocolType {
        case .sftp:
            let cmd = isDirectory ? "rmdir \"\(path)\"" : "rm \"\(path)\""
            _ = try runSFTP(commands: [cmd])
        case .ftp, .ftps:
            let cmd = isDirectory ? "RMD \(path)" : "DELE \(path)"
            _ = try runCurlFTP(quoteCommands: [cmd], path: path)
        }
    }

    func rename(oldPath: String, newPath: String) throws {
        switch site.protocolType {
        case .sftp:
            _ = try runSFTP(commands: ["rename \"\(oldPath)\" \"\(newPath)\""])
        case .ftp, .ftps:
            _ = try runCurlFTP(quoteCommands: ["RNFR \(oldPath)", "RNTO \(newPath)"], path: "")
        }
    }

    // MARK: - SFTP Engine
    private func runSFTP(commands: [String], customProcess: ((Process) -> Void)? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        var args = [
            "-b", "-",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=no",
            "-P", "\(site.port)"
        ]
        if !site.privateKeyPath.isEmpty {
            args.append(contentsOf: ["-i", NSString(string: site.privateKeyPath).expandingTildeInPath])
        }

        let userHost = site.username.isEmpty ? site.host : "\(site.username)@\(site.host)"
        args.append(userHost)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        var tempAskPassURL: URL?
        if !site.password.isEmpty {
            let tempScript = "#!/bin/sh\necho '\(site.password.replacingOccurrences(of: "'", with: "'\\''"))'\n"
            let askpassURL = FileManager.default.temporaryDirectory.appendingPathComponent("sftp-askpass-\(UUID().uuidString).sh")
            try? tempScript.write(to: askpassURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassURL.path)
            tempAskPassURL = askpassURL
            env["SSH_ASKPASS"] = askpassURL.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = ":0"
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        customProcess?(process)

        try process.run()

        let script = commands.joined(separator: "\n") + "\nbye\n"
        if let data = script.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if let temp = tempAskPassURL {
            try? FileManager.default.removeItem(at: temp)
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let msg = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PanelError(message: L("SFTP Hatası ({0}): {1}", process.terminationStatus, msg.isEmpty ? output : msg))
        }

        return output
    }

    private func listSFTP(path: String) throws -> [RemoteEntry] {
        let cleanPath = path.isEmpty ? "." : path
        let output = try runSFTP(commands: ["ls -la \"\(cleanPath)\""])
        return RemoteParser.parseUnixListing(output, basePath: path)
    }

    private func downloadSFTP(remotePath: String, to localURL: URL, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        if control.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        progress(0, 1, (remotePath as NSString).lastPathComponent)
        var runningProc: Process?
        _ = try runSFTP(commands: ["get \"\(remotePath)\" \"\(localURL.path)\""]) { proc in
            runningProc = proc
        }
        if control.cancelled {
            runningProc?.terminate()
            try? FileManager.default.removeItem(at: localURL)
            throw PanelError(message: L("İndirme iptal edildi."))
        }
        progress(1, 1, (remotePath as NSString).lastPathComponent)
    }

    private func uploadSFTP(localURL: URL, to remoteDir: String, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        if control.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        progress(0, 1, localURL.lastPathComponent)
        var runningProc: Process?
        let target = remoteDir.hasSuffix("/") ? "\(remoteDir)\(localURL.lastPathComponent)" : "\(remoteDir)/\(localURL.lastPathComponent)"
        _ = try runSFTP(commands: ["put \"\(localURL.path)\" \"\(target)\""]) { proc in
            runningProc = proc
        }
        if control.cancelled {
            runningProc?.terminate()
            throw PanelError(message: L("Yükleme iptal edildi."))
        }
        progress(1, 1, localURL.lastPathComponent)
    }

    // MARK: - FTP / FTPS Engine
    func buildCurlBaseArgs() -> [String] {
        var args = ["-s", "--connect-timeout", "15"]
        if site.protocolType == .ftps {
            args.append(contentsOf: ["--ssl-reqd"])
        }
        if !site.username.isEmpty {
            let auth = site.password.isEmpty ? site.username : "\(site.username):\(site.password)"
            args.append(contentsOf: ["--user", auth])
        }
        return args
    }

    private func runCurlFTP(quoteCommands: [String], path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = buildCurlBaseArgs()
        for q in quoteCommands {
            args.append(contentsOf: ["-Q", q])
        }

        let scheme = site.protocolType.curlScheme
        let fullURL = "\(scheme)://\(site.host):\(site.port)/"
        args.append(fullURL)

        process.arguments = args
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PanelError(message: L("FTP Hatası ({0}): {1}", process.terminationStatus, err))
        }

        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func listFTP(path: String) throws -> [RemoteEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = buildCurlBaseArgs()

        let scheme = site.protocolType.curlScheme
        var cleanPath = path
        if !cleanPath.hasPrefix("/") { cleanPath = "/" + cleanPath }
        if !cleanPath.hasSuffix("/") { cleanPath += "/" }

        let fullURL = "\(scheme)://\(site.host):\(site.port)\(cleanPath)"
        args.append(fullURL)

        process.arguments = args
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PanelError(message: L("FTP Dizin Hatası ({0}): {1}", process.terminationStatus, err))
        }

        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RemoteParser.parseUnixListing(out, basePath: path)
    }

    private func downloadFTP(remotePath: String, to localURL: URL, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        if control.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        progress(0, 1, (remotePath as NSString).lastPathComponent)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = buildCurlBaseArgs()
        args.append(contentsOf: ["-o", localURL.path])

        let scheme = site.protocolType.curlScheme
        let p = remotePath.hasPrefix("/") ? remotePath : "/\(remotePath)"
        args.append("\(scheme)://\(site.host):\(site.port)\(p)")

        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if control.cancelled {
            try? FileManager.default.removeItem(at: localURL)
            throw PanelError(message: L("İndirme iptal edildi."))
        }

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PanelError(message: L("FTP İndirme Hatası ({0}): {1}", process.terminationStatus, err))
        }

        progress(1, 1, (remotePath as NSString).lastPathComponent)
    }

    private func uploadFTP(localURL: URL, to remoteDir: String, control: JobState, progress: @escaping (Int, Int, String) -> Void) throws {
        if control.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        progress(0, 1, localURL.lastPathComponent)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = buildCurlBaseArgs()
        args.append(contentsOf: ["-T", localURL.path])

        let scheme = site.protocolType.curlScheme
        var cleanDir = remoteDir
        if !cleanDir.hasPrefix("/") { cleanDir = "/" + cleanDir }
        if !cleanDir.hasSuffix("/") { cleanDir += "/" }

        args.append("\(scheme)://\(site.host):\(site.port)\(cleanDir)")

        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if control.cancelled {
            throw PanelError(message: L("Yükleme iptal edildi."))
        }

        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PanelError(message: L("FTP Yükleme Hatası ({0}): {1}", process.terminationStatus, err))
        }

        progress(1, 1, localURL.lastPathComponent)
    }
}
