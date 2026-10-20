// SPDX-License-Identifier: GPL-3.0-only
import Foundation

func testUpdates() throws {
    let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.2.0", "1.10.0", "2.0.0"]
    for (a, b) in zip(ordered, ordered.dropFirst()) { assert(AppVersion(a)! < AppVersion(b)!, "\(a) must precede \(b)") }
    assert(AppVersion("v1.2.3+build.1") == AppVersion("1.2.3+different"))
    for invalid in ["", "1.0", "1.2.3.4", "01.2.3", "-1.2.3", "1.2.3-", "1.2.3-01", "1.2.3+", "1.2.3++a", "1.2.3/evil", "１.2.3"] { assert(AppVersion(invalid) == nil, invalid) }
    assert(AppVersion("1.0.0-999999999999999999999999")! > AppVersion("1.0.0-99999999999999999999999")!)
    let feed = Data("""
    [
      {"tag_name":"v9.0.0","draft":true,"prerelease":false},
      {"tag_name":"v1.10.0","draft":false,"prerelease":false},
      {"tag_name":"v2.0.0-beta.1","draft":false,"prerelease":true},
      {"tag_name":"v1.2.0","draft":false,"prerelease":false},
      {"tag_name":"not-a-version","draft":false,"prerelease":false},
      {"tag_name":"v3.0.0-alpha","draft":false,"prerelease":false}
    ]
    """.utf8)
    let result1 = try ReleaseFeed.newest(feed, status: 200, current: "1.0.0", includePreviews: false)?.tag
    assert(result1 == "v1.10.0")
    let result2 = try ReleaseFeed.newest(feed, status: 200, current: "1.0.0", includePreviews: true)?.tag
    assert(result2 == "v3.0.0-alpha")
    let result3 = try ReleaseFeed.newest(feed, status: 200, current: "4.0.0", includePreviews: true)
    assert(result3 == nil)
    let result4 = try ReleaseFeed.newest(Data("[]".utf8), status: 200, current: "1.0.0", includePreviews: true)
    assert(result4 == nil)
    func rejects(_ data: Data, _ status: Int) {
        do { _ = try ReleaseFeed.newest(data, status: status, current: "1.0.0", includePreviews: false); fatalError("Expected update feed error") } catch {}
    }
    rejects(feed, 403); rejects(feed, 429); rejects(feed, 500)
    rejects(Data("{invalid}".utf8), 200); rejects(Data(repeating: 32, count: 2_000_001), 200)
    let release = AppRelease(tag: "v1.10.0", draft: false, prerelease: false)
    assert(release.pageURL.absoluteString == "https://github.com/ferdisahin/total-command/releases/tag/v1.10.0")
    let now = Date(timeIntervalSince1970: 1_000_000)
    assert(!ReleaseFeed.isDue(interval: 0, lastAttempt: nil, now: now))
    assert(!ReleaseFeed.isDue(interval: 99, lastAttempt: nil, now: now))
    assert(ReleaseFeed.isDue(interval: 1, lastAttempt: nil, now: now))
    assert(!ReleaseFeed.isDue(interval: 1, lastAttempt: now.addingTimeInterval(-86_399), now: now))
    assert(ReleaseFeed.isDue(interval: 1, lastAttempt: now.addingTimeInterval(-86_400), now: now))
    assert(!ReleaseFeed.isDue(interval: 7, lastAttempt: now.addingTimeInterval(-86_400), now: now))
    assert(ReleaseFeed.isDue(interval: 7, lastAttempt: now.addingTimeInterval(-604_800), now: now))
    assert(ReleaseFeed.isDue(interval: 1, lastAttempt: now.addingTimeInterval(60), now: now))
    print("PASS: semantic versions, stable/preview channels, malformed feeds, HTTP errors, update schedule")
}
