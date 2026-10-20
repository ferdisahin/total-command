// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Foundation

struct AppVersion: Comparable {
    let numbers: [UInt]
    let prerelease: [String]

    init?(_ tag: String) {
        let text = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let build = text.split(separator: "+", omittingEmptySubsequences: false)
        guard build.count <= 2 else { return nil }
        func validIdentifiers(_ value: Substring) -> Bool {
            value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
            }
        }
        if build.count == 2 && !validIdentifiers(build[1]) { return nil }
        let parts = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let fields = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0") && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = fields.compactMap { UInt($0) }
        guard numbers.count == 3 else { return nil }
        var prerelease: [String] = []
        if parts.count == 2 {
            guard validIdentifiers(parts[1]) else { return nil }
            prerelease = parts[1].split(separator: ".").map(String.init)
            guard prerelease.allSatisfy({ !$0.utf8.allSatisfy { (48...57).contains($0) } || $0.count == 1 || $0.first != "0" }) else { return nil }
        }
        self.numbers = numbers; self.prerelease = prerelease
    }
    static func < (a: Self, b: Self) -> Bool {
        if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
        if a.prerelease.isEmpty || b.prerelease.isEmpty { return !a.prerelease.isEmpty && b.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            let xn = x.utf8.allSatisfy { (48...57).contains($0) }, yn = y.utf8.allSatisfy { (48...57).contains($0) }
            if xn && yn { return x.count == y.count ? x < y : x.count < y.count }
            if xn != yn { return xn }
            return x < y
        }
        return a.prerelease.count < b.prerelease.count
    }
}

struct AppRelease: Decodable {
    let tag: String
    let draft: Bool
    let prerelease: Bool
    var isPreview: Bool { prerelease || AppVersion(tag)?.prerelease.isEmpty == false }
    enum CodingKeys: String, CodingKey { case tag = "tag_name", draft, prerelease }
    var pageURL: URL {
        var components = URLComponents(string: "https://github.com/ferdisahin/total-command")!
        components.path = "/ferdisahin/total-command/releases/tag/" + tag
        return components.url!
    }
}

enum ReleaseFeed {
    static func newest(_ data: Data, status: Int, current: String, includePreviews: Bool) throws -> AppRelease? {
        guard status == 200 else {
            throw PanelError(message: status == 403 || status == 429 ? "GitHub istek sınırına ulaşıldı. Daha sonra yeniden deneyin." : "GitHub güncelleme bilgisi alınamadı (HTTP \(status)). Daha sonra yeniden deneyin.")
        }
        guard data.count <= 2_000_000, let installed = AppVersion(current) else { throw PanelError(message: "Sürüm bilgisi okunamadı.") }
        let releases: [AppRelease]
        do { releases = try JSONDecoder().decode([AppRelease].self, from: data) }
        catch { throw PanelError(message: "GitHub geçerli bir sürüm listesi döndürmedi. Daha sonra yeniden deneyin.") }
        return releases.filter {
            guard !$0.draft, let version = AppVersion($0.tag), version > installed else { return false }
            return includePreviews || !$0.isPreview
        }.max { AppVersion($0.tag)! < AppVersion($1.tag)! }
    }
    static func isDue(interval: Int, lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard interval == 1 || interval == 7 else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= Double(interval) * 86_400 || lastAttempt > now
    }
}

final class UpdateChecker {
    private let session: URLSession
    private var task: URLSessionDataTask?
    var isChecking: Bool { task != nil }
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }
    func check(current: String, includePreviews: Bool, completion: @escaping (Result<AppRelease?, Error>) -> Void) {
        guard task == nil else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/ferdisahin/total-command/releases?per_page=100")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TotalCommand/" + current, forHTTPHeaderField: "User-Agent")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<AppRelease?, Error>
            if let error { result = .failure(error) }
            else { result = Result { try ReleaseFeed.newest(data ?? Data(), status: (response as? HTTPURLResponse)?.statusCode ?? 0, current: current, includePreviews: includePreviews) } }
            DispatchQueue.main.async { self?.task = nil; completion(result) }
        }
        task?.resume()
    }
    deinit { task?.cancel(); session.invalidateAndCancel() }
}
