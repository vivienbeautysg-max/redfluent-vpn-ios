import Foundation

// Self-test for the multi-region + usage logic. Compiled by scripts/selftest.sh against the
// real source files (App/Regions.swift, App/UsageMetrics.swift, App/APIClient.swift,
// Tunnel/RuntimeConfigRequest.swift, Tunnel/SharedContainer.swift) — not copies.

var checks = 0
var failures = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String, line: UInt = #line) {
    checks += 1
    if condition() {
        print("  ok    \(name)")
    } else {
        failures += 1
        print("  FAIL  \(name)   (main.swift:\(line))")
    }
}

func section(_ title: String) { print("\n\(title)") }

func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

// MARK: 1. GET /profile decoding

section("1. /profile decoding (regions + isOwner)")

let oldProfile = """
{"ok":true,"enabled":true,"profileId":"p1","ownerLabel":"Kiki","serverRegion":"Tokyo","routingMode":"smart","monthlyQuotaGB":200}
"""
let ownerProfile = """
{"ok":true,"enabled":true,"profileId":"p2","ownerLabel":"Owner","serverRegion":"Tokyo","routingMode":"smart","monthlyQuotaGB":1000,
 "isOwner":true,"regions":[{"id":"tokyo","name":"Tokyo","isDefault":true},{"id":"singapore","name":"Singapore","isDefault":false}]}
"""
do {
    let old = try decode(ProfileResponse.self, oldProfile).status()
    check(old.regions == [.tokyo], "old backend (no regions key) -> [tokyo]")
    check(old.enabled && old.profileId == "p1" && old.monthlyQuotaGB == 200, "old backend: existing fields unchanged")

    let owner = try decode(ProfileResponse.self, ownerProfile).status()
    check(owner.enabled, "owner profile: decodes with the extra isOwner field present (it is not read)")
    check(owner.regions.map(\.id) == ["tokyo", "singapore"], "owner profile: region ids in order")
    check(owner.regions.map(\.name) == ["Tokyo", "Singapore"], "owner profile: region names")
    check(owner.regions.map(\.isDefault) == [true, false], "owner profile: isDefault flags")

    let empty = try decode(ProfileResponse.self, """
    {"ok":true,"enabled":true,"profileId":"p","ownerLabel":"x","serverRegion":"Tokyo","routingMode":"smart","regions":[]}
    """).status()
    check(empty.regions == [.tokyo], "empty regions array -> [tokyo]")

    let wrongShape = try decode(ProfileResponse.self, """
    {"ok":true,"enabled":true,"profileId":"p","ownerLabel":"x","serverRegion":"Tokyo","routingMode":"smart","regions":"oops"}
    """).status()
    check(wrongShape.regions == [.tokyo], "regions of the wrong type does not break /profile -> [tokyo]")

    let partlyBad = try decode(ProfileResponse.self, """
    {"ok":true,"enabled":false,"profileId":"p","ownerLabel":"x","serverRegion":"Tokyo","routingMode":"smart",
     "regions":[{"id":"tokyo","name":"Tokyo","isDefault":true},{"name":5},"x",{"id":"singapore"}]}
    """).status()
    check(partlyBad.regions.map(\.id) == ["tokyo", "singapore"], "bad elements are dropped, good ones kept")
    check(partlyBad.regions.last?.name == "Singapore", "missing name falls back to capitalised id")
    check(partlyBad.enabled == false, "revoke flag (enabled=false) still decoded next to bad regions")

    var rejected = false
    do { _ = try decode(ProfileResponse.self, #"{"ok":false,"error":"nope"}"#).status() } catch { rejected = true }
    check(rejected, "ok:false still throws")
} catch {
    check(false, "profile decoding threw: \(error)")
}

// MARK: 2. selection rules

section("2. region selection")

let both = [VPNRegion.tokyo, VPNRegion(id: "singapore", name: "Singapore")]
check(RegionPolicy.resolveSelection(stored: "singapore", offered: both) == "singapore", "offered selection is kept")
check(RegionPolicy.resolveSelection(stored: "singapore", offered: [.tokyo]) == "tokyo", "no longer offered -> tokyo")
check(RegionPolicy.resolveSelection(stored: nil, offered: both) == "tokyo", "nothing stored -> tokyo")
check(RegionPolicy.resolveSelection(stored: "mars", offered: both) == "tokyo", "unknown id -> tokyo")
check(RegionPolicy.offered(from: nil) == [.tokyo], "offered(nil) -> [tokyo]")
check(RegionPolicy.name(of: "singapore", in: both) == "Singapore", "name lookup")

let suiteName = "rfv.selftest.\(UUID().uuidString)"
let suite = UserDefaults(suiteName: suiteName)!
check(RegionStore.selectedID(suite) == "tokyo", "fresh defaults -> tokyo")
RegionStore.saveOffered(both, to: suite)
RegionStore.saveSelected("singapore", to: suite)
check(RegionStore.selectedID(suite) == "singapore", "selection round-trips")
check(RegionStore.offered(suite) == both, "offered list round-trips")
check(RegionStore.selectedRegion(suite).id == "singapore" && RegionStore.selectedRegion(suite).name == "Singapore",
      "selectedRegion() = singapore while still offered")
RegionStore.saveOffered([.tokyo], to: suite)
check(RegionStore.selectedRegion(suite).id == "tokyo", "selectedRegion() resets to tokyo when no longer offered")
check(RegionStore.active(suite) == nil, "no active region before the tunnel writes one")
suite.set(["id": "singapore", "name": "Singapore"], forKey: SharedContainer.activeRegionKey)
check(RegionStore.active(suite) == ActiveRegion(id: "singapore", name: "Singapore"),
      "app reads what the tunnel wrote (key shared)")
check(SharedContainer.activeRegionKey == RegionStore.activeKey, "tunnel and app use the same active-region key")

// MARK: 3. runtime-config request

section("3. /device/runtime-config URL + rules")

let base = "https://vpn-api.redfluent.com"
check(RuntimeConfigRequest.url(base: base, region: "tokyo")?.absoluteString == base + "/device/runtime-config",
      "tokyo: today's URL, no query")
check(RuntimeConfigRequest.url(base: base, region: "singapore")?.absoluteString == base + "/device/runtime-config?region=singapore",
      "singapore: ?region=singapore appended")
check(RuntimeConfigRequest.url(base: base, region: "singapore")?.query == "region=singapore",
      "the '?' is a real query separator (not %3F)")
check(RuntimeConfigRequest.url(base: base, region: "a b&c")?.absoluteString == base + "/device/runtime-config?region=a%20b%26c",
      "odd ids are percent-encoded")
check(RuntimeConfigRequest.confirms(region: "singapore", in: ["region": "singapore", "ok": true]), "confirms: echoed region matches")
check(RuntimeConfigRequest.confirms(region: "singapore", in: ["region": "Singapore"]), "confirms: case-insensitive")
check(!RuntimeConfigRequest.confirms(region: "singapore", in: ["ok": true, "serverRegion": "Tokyo"]),
      "confirms: old backend that ignores ?region (no echo) is rejected")
check(!RuntimeConfigRequest.confirms(region: "singapore", in: ["region": "tokyo"]), "confirms: wrong region is rejected")
check(RuntimeConfigRequest.serverReason(from: Data(#"{"ok":false,"error":"region not allowed"}"#.utf8)) == "region not allowed",
      "403 body -> reason text")
check(RuntimeConfigRequest.serverReason(from: Data("<html>".utf8)) == nil, "non-JSON body -> nil")
check(RuntimeConfigRequest.failureMessage(region: "singapore", detail: "HTTP 403: region not allowed")
      == "Singapore server unavailable: HTTP 403: region not allowed", "failure message text")
check(RuntimeConfigRequest.isDefault(region: "tokyo") && !RuntimeConfigRequest.isDefault(region: "singapore"),
      "only tokyo may fall back to the bundled config")

// MARK: 4. usage

section("4. usage levels, formatting, grouping")

check(UsageLevel(percent: 0) == .ok, "0% ok")
check(UsageLevel(percent: 69.9) == .ok, "69.9% ok")
check(UsageLevel(percent: 70.0) == .warning, "70.0% warning")
check(UsageLevel(percent: 89.9) == .warning, "89.9% warning")
check(UsageLevel(percent: 90.0) == .critical, "90.0% critical")
check(UsageLevel(percent: 104.0) == .critical, "104% critical")
check(UsageFormat.amount(used: 12.34, quota: 1000) == "12.3 / 1000 GB", "amount with quota")
check(UsageFormat.amount(used: 12.34, quota: nil) == "12.3 GB", "amount without quota")
check(UsageFormat.amount(used: 5, quota: 0) == "5.0 GB", "quota 0 treated as no quota")
check(UsageFormat.amount(used: 1, quota: 12.5) == "1.0 / 12.5 GB", "fractional quota keeps its decimal")
check(UsageFormat.percent(93.8) == "93.8%", "percent text")
check(UsageFormat.total(461.3) == "461.3 GB", "group total has one decimal")

func device(_ id: String, label: String?, name: String, model: String?, app: String?, enabled: Bool = true) -> String {
    let lbl = label.map { "\"\($0)\"" } ?? "null"
    let mdl = model.map { "\"\($0)\"" } ?? "null"
    let ver = app.map { "\"\($0)\"" } ?? "null"
    return """
    {"profileId":"\(id)","inviteCode":"CODE-\(label ?? "x")","inviteLabel":\(lbl),"displayName":"\(name)","deviceName":\(mdl),
     "appVersion":\(ver),"ownerLabel":"Owner","enabled":\(enabled),"connected":false,"inUse":false,"createdAt":"2026-06-01 08:00:00"
    __USAGE__}
    """
}

let withUsage = """
{"ok":true,"period":{"start":"2026-10-01T00:00:00.000Z","end":"2026-11-01T00:00:00.000Z"},"devices":[
 \(device("d1", label: "Alice", name: "Alice iPhone", model: "iPhone 15", app: "1.0 (39)").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":187.6,"quotaGB":200,"percent":93.8,"uploadGB":20,"downloadGB":167.6}"#)),
 \(device("d2", label: "Alice", name: "Alice iPad", model: nil, app: nil).replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":41.2,"quotaGB":200,"percent":20.6,"uploadGB":1,"downloadGB":40.2}"#)),
 \(device("d3", label: "Max", name: "Max iPhone", model: "iPhone 17", app: "1.1 (41)").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":312.4,"quotaGB":1000,"percent":null,"uploadGB":1,"downloadGB":311.4}"#)),
 \(device("d4", label: "Max", name: "Max Desktop", model: "PC", app: "0.1.0").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":148.9,"quotaGB":null,"percent":null,"uploadGB":1,"downloadGB":147.9}"#)),
 \(device("d5", label: "Zed", name: "Zed over quota", model: "Pixel", app: "1.1", enabled: false).replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":260,"quotaGB":200,"percent":130,"uploadGB":1,"downloadGB":259}"#)),
 \(device("d6", label: "Quiet", name: "No usage object", model: "x", app: "1").replacingOccurrences(of: "__USAGE__", with: ""))
]}
"""

do {
    let result = try decode(OwnerDevicesResponse.self, withUsage)
    check(result.devices?.count == 6, "all 6 devices decode")
    check(result.period?.start == "2026-10-01T00:00:00.000Z" && result.period?.end == "2026-11-01T00:00:00.000Z", "period decodes")
    check(UsageMetrics.periodText(result.period) == "since 1 Oct", "period text = 'since 1 Oct'")
    check(UsageMetrics.periodText(UsagePeriod(start: "2026-10-01", end: nil)) == "since 1 Oct", "date-only period start")
    check(UsageMetrics.periodText(nil) == nil, "no period -> no text")

    let groups = UsageMetrics.groups(devices: result.devices ?? [], usage: result.usage)
    // totals: Max 461.3, Alice 228.8, Zed 260.0  ->  Max, Zed, Alice
    check(groups.map(\.label) == ["Max", "Zed", "Alice"], "users sorted by total used desc (Max 461.3, Zed 260.0, Alice 228.8)")
    check(!groups.contains(where: { $0.label == "Quiet" }), "device without a usage object is not listed")

    let alice = groups.first(where: { $0.label == "Alice" })!
    check(abs(alice.totalGB - 228.8) < 0.0001, "Alice total = 228.8")
    check(alice.rows.map(\.displayName) == ["Alice iPhone", "Alice iPad"], "devices sorted by used desc")
    check(alice.rows[0].detail == "iPhone 15 \u{00B7} 1.0 (39)", "detail = 'deviceName · app version'")
    check(alice.rows[1].detail == nil, "no model and no version -> no detail line")
    check(alice.rows[0].amountText == "187.6 / 200 GB" && alice.rows[0].percentText == "93.8%", "row texts")
    check(alice.rows[0].level == .critical && alice.rows[1].level == .ok, "93.8% critical, 20.6% ok")

    let maxGroup = groups.first(where: { $0.label == "Max" })!
    check(maxGroup.rows[0].percent != nil && abs(maxGroup.rows[0].percent! - 31.24) < 0.001, "missing percent is computed from used/quota")
    check(maxGroup.rows[1].percent == nil && maxGroup.rows[1].fraction == nil && maxGroup.rows[1].amountText == "148.9 GB",
          "quota null -> no percent, no bar, 'used GB' only")

    let zed = groups.first(where: { $0.label == "Zed" })!
    check(zed.rows[0].fraction == 1.0 && zed.rows[0].percentText == "130.0%" && zed.rows[0].level == .critical,
          "over quota: bar clamps to full, label shows the real percent")
    check(zed.rows[0].enabled == false, "revoked flag carried to the row")
} catch {
    check(false, "owner devices decoding threw: \(error)")
}

section("5. /owner/devices from an older backend and from a broken new one")

let oldDevices = """
{"ok":true,"devices":[\(device("d1", label: "Alice", name: "Alice iPhone", model: "iPhone", app: "1.0").replacingOccurrences(of: "__USAGE__", with: ""))]}
"""
do {
    let r = try decode(OwnerDevicesResponse.self, oldDevices)
    check(r.devices?.count == 1, "old backend: device list decodes")
    check(r.usage.isEmpty && r.period == nil, "old backend: no usage, no period")
    check(UsageMetrics.groups(devices: r.devices ?? [], usage: r.usage).isEmpty, "old backend: Usage section stays hidden")
} catch {
    check(false, "old backend decode threw: \(error)")
}

let brokenUsage = """
{"ok":true,"period":"later","devices":[\(device("d1", label: "Alice", name: "Alice iPhone", model: "iPhone", app: "1.0").replacingOccurrences(of: "__USAGE__", with: #","usage":"lots""#)),
 \(device("d2", label: "Alice", name: "Alice iPad", model: "iPad", app: "1.0").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":"many","quotaGB":200}"#)),
 \(device("d3", label: "Alice", name: "Alice Mac", model: "Mac", app: "1.0").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":3.5,"quotaGB":200}"#)),
 \(device("d4", label: "Alice", name: "Alice Watch", model: "Watch", app: "1.0").replacingOccurrences(of: "__USAGE__", with: #","usage":{"usedGB":2.0,"quotaGB":"lots"}"#))]}
"""
do {
    let r = try decode(OwnerDevicesResponse.self, brokenUsage)
    check(r.devices?.count == 4, "malformed usage/period never breaks the device list")
    check(r.period == nil || r.period?.start == nil, "malformed period -> ignored")
    let g = UsageMetrics.groups(devices: r.devices ?? [], usage: r.usage)
    check(g.count == 1 && g[0].rows.map(\.displayName) == ["Alice Mac", "Alice Watch"],
          "devices without a usable usedGB are left out, the rest are listed")
    check(g[0].rows[0].percent.map { abs($0 - 1.75) < 0.0001 } == true, "percent computed when the backend omitted it")
    check(g[0].rows[1].quotaGB == nil && g[0].rows[1].amountText == "2.0 GB",
          "wrong-typed quotaGB is read as missing (usedGB still shown)")
} catch {
    check(false, "broken usage decode threw: \(error)")
}

// MARK: 6. malformed isOwner / regions never fail /profile (fix 4)

section("6. malformed isOwner + regions together never fail /profile (revoke flag must survive)")

let profileBase = #""ok":true,"enabled":false,"profileId":"p","ownerLabel":"x","serverRegion":"Tokyo","routingMode":"smart""#
let malformedExtras = [
    #""isOwner":"yes","regions":"oops""#,
    #""isOwner":{"a":[1,2]},"regions":{"id":"singapore"}"#,
    #""isOwner":null,"regions":[1,"x",null,{"id":""}]"#,
    #""isOwner":42,"regions":[{"id":"tokyo","name":{"bad":true}}]"#,
    #""isOwner":[],"regions":[[],[[]]]"#,
]
for (i, extra) in malformedExtras.enumerated() {
    do {
        let status = try decode(ProfileResponse.self, "{\(profileBase),\(extra)}").status()
        check(status.enabled == false && status.regions == [.tokyo], "malformed variant \(i + 1): decodes, enabled=false kept, regions -> [tokyo]")
    } catch {
        check(false, "malformed variant \(i + 1) threw: \(error)")
    }
}

// MARK: 7. region edge cases (fix 6)

section("7. region edge cases: empty ids, duplicates, fallback, case")

check(RegionPolicy.offered(from: [VPNRegion(id: "", name: "x"), VPNRegion(id: "   ", name: "y")]) == [.tokyo],
      "regions with an empty id are ignored (nothing usable -> [tokyo])")
let dupes = RegionPolicy.offered(from: [VPNRegion(id: "Singapore", name: "A"), VPNRegion(id: "singapore", name: "B"), VPNRegion.tokyo])
check(dupes.map(\.name) == ["A", "Tokyo"], "repeated ids (any case) keep the first")
do {
    let trimmed = try decode(ProfileResponse.self, #"{"ok":true,"enabled":true,"profileId":"p","ownerLabel":"x","serverRegion":"T","routingMode":"s","regions":[{"id":"  singapore "},{"id":""}]}"#).status()
    check(trimmed.regions.map(\.id) == ["singapore"], "ids are trimmed and the empty one is dropped at decode")
} catch { check(false, "trim decode threw: \(error)") }

let osakaDefault = [VPNRegion(id: "singapore", name: "Singapore"), VPNRegion(id: "osaka", name: "Osaka", isDefault: true)]
check(RegionPolicy.resolveSelection(stored: "tokyo", offered: osakaDefault) == "osaka", "selection not offered -> the server's isDefault region")
check(RegionPolicy.resolveSelection(stored: nil, offered: osakaDefault) == "osaka", "nothing stored -> the server's isDefault region")
let noDefault = [VPNRegion(id: "singapore", name: "Singapore"), VPNRegion(id: "osaka", name: "Osaka")]
check(RegionPolicy.resolveSelection(stored: "tokyo", offered: noDefault) == "singapore", "no isDefault flag -> the first region")
check(RegionPolicy.resolveSelection(stored: "SINGAPORE", offered: both) == "singapore", "case-insensitive match returns the server's spelling")
check(RegionPolicy.resolveSelection(stored: "Singapore", offered: [VPNRegion(id: "Singapore", name: "SG"), .tokyo]) == "Singapore",
      "server spelling kept even when it is not lowercase (so the picker tag matches)")
check(RegionPolicy.name(of: "SINGAPORE", in: both) == "Singapore", "name lookup is case-insensitive")
check(RegionPolicy.matches("Tokyo", "tOKYO") && !RegionPolicy.matches("tokyo", "singapore"), "matches()")
check(RegionPolicy.isDefault("TOKYO") && RegionPolicy.isDefault("Tokyo") && !RegionPolicy.isDefault("singapore"), "isDefault is case-insensitive")
check(RuntimeConfigRequest.isDefault(region: "Tokyo") && RuntimeConfigRequest.isDefault(region: "TOKYO"), "extension: Tokyo in any case is the default region")
check(RuntimeConfigRequest.url(base: base, region: "Tokyo")?.absoluteString == base + "/device/runtime-config", "extension: 'Tokyo' sends today's request")
check(RuntimeConfigRequest.url(base: base, region: "Singapore")?.query == "region=Singapore", "extension: non-default id is sent as given")

let mixedSuite = UserDefaults(suiteName: suiteName + ".mixed")!
RegionStore.saveOffered(both, to: mixedSuite)
RegionStore.saveSelected("Singapore", to: mixedSuite)
check(RegionStore.selectedRegion(mixedSuite).id == "singapore", "stored 'Singapore' resolves to the offered 'singapore'")
mixedSuite.removePersistentDomain(forName: suiteName + ".mixed")

// MARK: 8. what the Server row shows (fix 5)

section("8. Server row / In use caption / unavailable suite")

let sg = ActiveRegion(id: "singapore", name: "Singapore")
check(RegionPolicy.serverDisplayName(regions: both, selectedID: "singapore", connected: true, active: nil, profileRegion: "Tokyo") == "—",
      "connected + active region unknown -> '—' (not the selection)")
check(RegionPolicy.serverDisplayName(regions: both, selectedID: "tokyo", connected: true, active: sg, profileRegion: "Tokyo") == "Singapore",
      "connected -> what the tunnel really started with")
check(RegionPolicy.serverDisplayName(regions: both, selectedID: "singapore", connected: false, active: sg, profileRegion: "Tokyo") == "Singapore",
      "disconnected -> the selection")
check(RegionPolicy.serverDisplayName(regions: [.tokyo], selectedID: "tokyo", connected: true, active: nil, profileRegion: "Tokyo") == "Tokyo",
      "single region keeps the profile's region (today's UI), connected or not")
check(RegionPolicy.inUseCaption(connected: false, active: nil, selectedID: "singapore") == nil, "not connected -> no caption")
check(RegionPolicy.inUseCaption(connected: true, active: nil, selectedID: "singapore") == "—", "connected + unknown -> '—'")
check(RegionPolicy.inUseCaption(connected: true, active: sg, selectedID: "SINGAPORE") == nil, "connected + same region (any case) -> no caption")
check(RegionPolicy.inUseCaption(connected: true, active: sg, selectedID: "tokyo") == "Singapore", "connected + different region -> its name")
// Plant values in the process's private defaults: a "no suite" read must not fall back to them.
UserDefaults.standard.set(["id": "singapore", "name": "Singapore"], forKey: RegionStore.activeKey)
UserDefaults.standard.set("singapore", forKey: RegionStore.selectedKey)
check(RegionStore.active(nil) == nil, "no App Group suite -> active region is unknown (no fallback to private defaults)")
check(RegionStore.selectedID(nil) == "tokyo" && RegionStore.offered(nil) == [.tokyo], "no suite -> tokyo / [tokyo]")
UserDefaults.standard.removeObject(forKey: RegionStore.activeKey)
UserDefaults.standard.removeObject(forKey: RegionStore.selectedKey)

// MARK: 9. which disconnects count as a failed start (fix 1)

section("9. start-attempt tracking: only an attempt the app began that never connected")

let t0 = Date(timeIntervalSince1970: 1_000_000)
var tracker = StartAttemptTracker()
tracker.begin(regionID: "singapore", now: t0)
check(tracker.attemptForDisconnect(now: t0 + 2) == StartAttempt(startedAt: t0, regionID: "singapore"),
      "app-started attempt that drops to disconnected -> reportable")

tracker = StartAttemptTracker()
tracker.begin(regionID: "tokyo", now: t0)
tracker.reachedConnected()
check(tracker.attemptForDisconnect(now: t0 + 30) == nil,
      "connected -> reasserting -> disconnected (network change / on-demand) -> NOT a start failure, even inside the window")
check(tracker.attemptForDisconnect(now: t0 + 600) == nil, "... and not later either")

tracker = StartAttemptTracker()
check(tracker.attemptForDisconnect(now: t0) == nil, "start that iOS triggered by itself (no app attempt) -> not reportable")

tracker = StartAttemptTracker()
tracker.begin(regionID: "singapore", now: t0)
tracker.cancel()
check(tracker.attemptForDisconnect(now: t0 + 1) == nil, "user disconnects / startVPNTunnel threw -> not reportable")

tracker = StartAttemptTracker()
tracker.begin(regionID: "singapore", now: t0)
check(tracker.attemptForDisconnect(now: t0 + StartAttemptTracker.window + 1) == nil, "an attempt older than the window expires")
check(tracker.attempt == nil, "expired attempt is dropped")

tracker = StartAttemptTracker()
tracker.begin(regionID: "singapore", now: t0)
tracker.finish()
check(tracker.attemptForDisconnect(now: t0 + 1) == nil, "reported once, not again")

tracker = StartAttemptTracker()
tracker.begin(regionID: "singapore", now: t0)
check(tracker.attemptForDisconnect(now: t0 + 1) != nil && tracker.attemptForDisconnect(now: t0 + 2) != nil,
      "looking at a disconnect does not consume the attempt (a stale one must not eat the real failure)")
tracker.begin(regionID: "tokyo", now: t0 + 10)
check(tracker.attempt?.regionID == "tokyo", "a new attempt replaces the old one")

// MARK: 10. start-error channel (fix 3)

section("10. start-error file: extension -> app, never stale")

let failedAt = Date(timeIntervalSince1970: 2_000_000)
let record = SharedContainer.encodeStartError(message: "Singapore server unavailable: HTTP 403: region not allowed", at: failedAt)
check(TunnelStartError.message(from: record, since: failedAt - 5) == "Singapore server unavailable: HTTP 403: region not allowed",
      "message written by the extension is read by the app")
check(TunnelStartError.message(from: record, since: failedAt + 0.5) != nil, "1 s of clock slack")
check(TunnelStartError.message(from: record, since: failedAt + 30) == nil, "an error older than this attempt is ignored (no stale errors)")
check(TunnelStartError.message(from: nil, since: failedAt) == nil, "no file -> nil")
check(TunnelStartError.message(from: Data("garbage".utf8), since: failedAt) == nil, "garbage file -> nil")
check(TunnelStartError.message(from: SharedContainer.encodeStartError(message: "", at: failedAt), since: failedAt - 5) == nil, "empty message -> nil")
let longRecord = SharedContainer.encodeStartError(message: String(repeating: "x", count: 900), at: failedAt)
check(TunnelStartError.message(from: longRecord, since: failedAt - 5)?.count == 500, "message is capped at 500 characters")
check(SharedContainer.startErrorFileName == TunnelStartError.fileName, "extension and app use the same file name")

// MARK: 11. saved configuration follows the selection (fix 2)

section("11. saved providerConfiguration / on-demand rule")

let singaporeRegion = VPNRegion(id: "singapore", name: "Singapore")
let merged = RegionPolicy.providerConfiguration(["token": "T", "apiBase": "https://x", "configProfile": "p", "region": "tokyo"], region: singaporeRegion)
check(merged["region"] as? String == "singapore", "region replaced")
check(merged["token"] as? String == "T" && merged["apiBase"] as? String == "https://x" && merged["configProfile"] as? String == "p",
      "token, apiBase and the rest are kept")
check(RegionPolicy.providerConfiguration(nil, region: singaporeRegion)["region"] as? String == "singapore", "no saved configuration -> just the region")
check(RegionPolicy.serverAddress(for: singaporeRegion) == "RedFluent Singapore" && RegionPolicy.serverAddress(for: .tokyo) == "RedFluent Tokyo",
      "serverAddress")
check(RegionPolicy.disablesOnDemandAfterFailure(regionID: "singapore"), "failed non-default start -> on-demand off")
check(!RegionPolicy.disablesOnDemandAfterFailure(regionID: "tokyo") && !RegionPolicy.disablesOnDemandAfterFailure(regionID: "Tokyo"),
      "Tokyo keeps today's on-demand behaviour")

// MARK: 12. usage numbers that are not finite or are negative (fix 7)

section("12. usage: non-finite / negative values")

let weirdIDs = ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9"]
let weirdDevicesJSON = weirdIDs
    .map { id in device(id, label: "U", name: "dev-" + id, model: nil, app: nil).replacingOccurrences(of: "__USAGE__", with: "") }
    .joined(separator: ",")
let plainDevices = (try? decode(OwnerDevicesResponse.self, "{\"ok\":true,\"devices\":[" + weirdDevicesJSON + "]}"))?.devices ?? []
check(plainDevices.count == 9, "9 plain devices decoded for the usage checks")
let weird: [String: DeviceUsage] = [
    "d1": DeviceUsage(usedGB: .nan, quotaGB: 100, percent: 10),
    "d2": DeviceUsage(usedGB: .infinity, quotaGB: 100, percent: 10),
    "d3": DeviceUsage(usedGB: -5, quotaGB: 100, percent: nil),
    "d4": DeviceUsage(usedGB: 10, quotaGB: 100, percent: -50),
    "d5": DeviceUsage(usedGB: 10, quotaGB: 100, percent: .nan),
    "d6": DeviceUsage(usedGB: 10, quotaGB: .infinity, percent: 50),
    "d7": DeviceUsage(usedGB: 1e308, quotaGB: 1e-300, percent: nil),
    "d8": DeviceUsage(usedGB: 25, quotaGB: 100, percent: .infinity),
    "d9": DeviceUsage(usedGB: 3, quotaGB: -10, percent: 5),
]
let weirdRows = (UsageMetrics.groups(devices: plainDevices, usage: weird).first?.rows ?? [])
func weirdRow(_ id: String) -> UsageRow? { weirdRows.first(where: { $0.id == id }) }
check(weirdRow("d1") == nil && weirdRow("d2") == nil, "usedGB NaN / infinite -> device not listed")
check(weirdRow("d3")?.usedGB == 0 && weirdRow("d3")?.percent == 0 && weirdRow("d3")?.fraction == 0, "negative usedGB counts as 0 (0%, empty bar)")
check(weirdRow("d4")?.percent == 0 && weirdRow("d4")?.fraction == 0, "negative percent clamps to 0")
check(abs((weirdRow("d5")?.percent ?? -1) - 10) < 1e-9, "NaN percent is recomputed from used / quota")
check(weirdRow("d6")?.quotaGB == nil && weirdRow("d6")?.fraction == nil && weirdRow("d6")?.amountText == "10.0 GB", "infinite quota -> no quota, no bar")
check(weirdRow("d7")?.percent == nil && weirdRow("d7")?.fraction == nil, "used / quota overflowing to infinity -> no percent, no bar")
check(abs((weirdRow("d8")?.percent ?? -1) - 25) < 1e-9, "infinite percent is recomputed")
check(weirdRow("d9")?.quotaGB == nil && weirdRow("d9")?.fraction == nil, "negative quota -> no quota, no bar")
check(weirdRows.allSatisfy { $0.fraction.map { $0.isFinite && $0 >= 0 && $0 <= 1 } ?? true }, "every bar fraction is finite and within 0...1")
check(UsageRow(id: "x", displayName: "x", detail: nil, usedGB: 1, quotaGB: 1, percent: .nan, enabled: true).fraction == 0, "a NaN percent can never become a width")
check(UsageRow(id: "x", displayName: "x", detail: nil, usedGB: 1, quotaGB: 1, percent: .infinity, enabled: true).fraction == 0, "an infinite percent can never become a width")
if let total = UsageMetrics.groups(devices: plainDevices, usage: weird).first?.totalGB {
    check(total.isFinite && total >= 0, "group total is finite")
} else { check(false, "weird usage produced no group") }

// MARK: 13. 1.2: a device whose region the server decides sends no region parameter

section("13. 1.2: server-decided devices (everyone but the owner) request without a region parameter")

check(RuntimeConfigRequest.regionParameter(region: "singapore", serverDecides: true) == nil,
      "server-decided + assigned Singapore: no region parameter")
check(RuntimeConfigRequest.regionParameter(region: "tokyo", serverDecides: true) == nil, "server-decided + Tokyo: no region parameter")
check(RuntimeConfigRequest.regionParameter(region: "singapore", serverDecides: false) == "singapore", "owner: the picked region is sent")
check(RuntimeConfigRequest.regionParameter(region: "Tokyo", serverDecides: false) == nil, "owner on Tokyo: today's request")
check(RuntimeConfigRequest.url(base: base, region: RuntimeConfigRequest.regionParameter(region: "singapore", serverDecides: true))?.absoluteString
      == base + "/device/runtime-config", "non-owner assigned Singapore: the URL has no query at all")
check(RuntimeConfigRequest.url(base: base, region: nil)?.absoluteString == base + "/device/runtime-config", "url(region: nil) = today's request")
check(RuntimeConfigRequest.url(base: base, region: RuntimeConfigRequest.regionParameter(region: "singapore", serverDecides: false))?.query == "region=singapore",
      "owner on Singapore: ?region=singapore")
let serverCfg = RegionPolicy.providerConfiguration(["token": "T"], region: VPNRegion(id: "singapore", name: "Singapore"), serverDecides: true)
check(serverCfg["regionMode"] as? String == "server" && serverCfg["region"] as? String == "singapore" && serverCfg["token"] as? String == "T",
      "saved configuration says 'server' mode, keeps the last known region and the token")
check(RegionPolicy.providerConfiguration(nil, region: .tokyo, serverDecides: false)["regionMode"] as? String == "explicit", "owner: 'explicit' mode")
let modeSuite = UserDefaults(suiteName: suiteName + ".mode")!
RegionStore.saveOffered([.tokyo], to: modeSuite)
check(RegionStore.isServerDecided(modeSuite), "one offered region -> the server decides")
RegionStore.saveOffered(both, to: modeSuite)
check(!RegionStore.isServerDecided(modeSuite), "several offered regions (owner) -> picked by hand")
modeSuite.removePersistentDomain(forName: suiteName + ".mode")
check(RegionPolicy.serverDisplayName(regions: [VPNRegion(id: "singapore", name: "Singapore", isDefault: true)], selectedID: "singapore",
                                     connected: false, active: nil, profileRegion: "Tokyo") == "Singapore",
      "member assigned Singapore: the server's region, not a stale profile copy")
check(RegionPolicy.serverDisplayName(regions: [.tokyo], selectedID: "tokyo", connected: true, active: sg, profileRegion: "Tokyo") == "Singapore",
      "member whose tunnel followed to Singapore: what the tunnel runs")

// MARK: 14. the follow decision (pure)

section("14. follow decision: same region keeps, other region reloads, expired/revoked stops, network errors keep")

check(FollowPolicy.decide(active: "tokyo", outcome: .config(region: "tokyo")) == .keep, "same region -> keep (no-op)")
check(FollowPolicy.decide(active: "tokyo", outcome: .config(region: "Tokyo")) == .keep, "same region in another case -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .config(region: "singapore")) == .reload(region: "singapore"), "different region -> reload")
check(FollowPolicy.decide(active: "singapore", outcome: .config(region: "tokyo")) == .reload(region: "tokyo"), "back to Tokyo -> reload")
check(FollowPolicy.decide(active: "tokyo", outcome: .config(region: nil)) == .keep, "answer without a region (older backend) -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .config(region: "")) == .keep, "empty region -> keep")
check(FollowPolicy.decide(active: "singapore", outcome: .http(status: 403, error: "invite expired")) == .stop(.expired), "403 invite expired -> stop (expired)")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 401, error: "unauthorized")) == .stop(.revoked), "401 -> stop (revoked)")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 403, error: "device revoked")) == .stop(.revoked), "403 device revoked -> stop (revoked)")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 403, error: "region not allowed")) == .keep, "403 region not allowed -> keep (about the region, not the account)")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 503, error: "region unavailable")) == .keep, "503 region unavailable -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 500, error: nil)) == .keep, "500 -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 502, error: "bad gateway")) == .keep, "502 -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 429, error: "slow down")) == .keep, "429 -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 403, error: nil)) == .keep, "403 without the server's JSON error (a CDN page) -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .http(status: 401, error: nil)) == .keep, "401 without a JSON error -> keep")
check(FollowPolicy.decide(active: "singapore", outcome: .http(status: 200, error: "region not confirmed")) == .keep, "region not confirmed -> keep")
check(FollowPolicy.decide(active: "tokyo", outcome: .network) == .keep, "network error -> keep running, retry next tick")
check(FollowPolicy.stopKind(status: 401, error: "token expired") == .revoked, "an expired login token (401) is not 'invite expired'")
check(FollowPolicy.blocksStart(.http(status: 403, error: "invite expired")), "start: an expired invite never connects")
check(!FollowPolicy.blocksStart(.http(status: 401, error: "unauthorized")), "start: 401 keeps today's behaviour")
check(!FollowPolicy.blocksStart(.http(status: 403, error: "device revoked")), "start: revoked keeps today's behaviour")
check(!FollowPolicy.blocksStart(.network) && !FollowPolicy.blocksStart(.config(region: "tokyo")), "start: network / success are not blocked")
check(FollowPolicy.interval == 300, "one check every 5 minutes")
check(FollowPolicy.minGap >= 30 && FollowPolicy.pathDebounce >= 10, "checks are rate limited (battery)")
let wifi = FollowPolicy.PathSignature(satisfied: true, interfaces: ["en0"])
let cell = FollowPolicy.PathSignature(satisfied: true, interfaces: ["pdp_ip0"])
let none = FollowPolicy.PathSignature(satisfied: false, interfaces: [])
check(!FollowPolicy.pathChangeWarrantsCheck(previous: nil, current: wifi), "first path observation is only the current state")
check(!FollowPolicy.pathChangeWarrantsCheck(previous: wifi, current: wifi), "same path -> no check")
check(FollowPolicy.pathChangeWarrantsCheck(previous: wifi, current: cell), "Wi-Fi -> cellular -> check")
check(!FollowPolicy.pathChangeWarrantsCheck(previous: wifi, current: none), "network lost -> nothing to fetch over")
check(FollowPolicy.pathChangeWarrantsCheck(previous: none, current: wifi), "network back -> check")

// MARK: 15. the stop record (extension -> app)

section("15. server stop record: kinds, lock, parity with the app")

let stopAt = Date(timeIntervalSince1970: 3_000_000)
let expiredRec = SharedContainer.encodeStartError(message: StopKind.expired.message, at: stopAt, kind: StopKind.expired.rawValue)
let revokedRec = SharedContainer.encodeStartError(message: StopKind.revoked.message, at: stopAt, kind: StopKind.revoked.rawValue)
let startRec = SharedContainer.encodeStartError(message: "boom", at: stopAt)
check(SharedContainer.stopKind(in: expiredRec) == .expired && SharedContainer.stopKind(in: revokedRec) == .revoked, "extension reads the stop kinds back")
check(SharedContainer.stopKind(in: startRec) == nil && SharedContainer.stopKind(in: nil) == nil
      && SharedContainer.stopKind(in: Data("junk".utf8)) == nil, "a plain start failure / garbage is not a stop lock")
check(TunnelStartError.standingStop(from: expiredRec) == .expired && TunnelStartError.standingStop(from: revokedRec) == .revoked, "app sees the same stop kinds")
check(TunnelStartError.standingStop(from: startRec) == nil, "app: a start failure is not a stop")
check(TunnelStartError.standingStop(from: expiredRec) == ServerStop(rawValue: StopKind.expired.rawValue), "app and extension use the same raw values")
check(Set(["expired", "revoked"]) == Set([StopKind.expired.rawValue, StopKind.revoked.rawValue])
      && ServerStop(rawValue: "expired") != nil && ServerStop(rawValue: "revoked") != nil, "ServerStop and StopKind raw values match")
check(TunnelStartError.message(from: expiredRec, since: stopAt - 5) == nil, "a server stop is never shown as a failed start")
check(TunnelStartError.message(from: startRec, since: stopAt - 5) == "boom", "a start failure still is")
check(TunnelStartError.entry(from: expiredRec, since: stopAt - 5)?.stop == .expired && TunnelStartError.entry(from: expiredRec, since: stopAt - 5)?.message == "Invite expired",
      "entry carries kind and the text for Diagnostics")
check(TunnelStartError.entry(from: expiredRec, since: stopAt + 600) == nil, "recent-only reads ignore an old record")
check(TunnelStartError.standingStop(from: expiredRec) != nil, "the lock does not depend on age")
check(StopKind.expired.message == "Invite expired" && StopKind.revoked.message == "Access revoked", "texts shown to the user")

// MARK: 16. expired / days-left display

section("16. dashboard expiry text")

let utc = TimeZone(secondsFromGMT: 0)!
let sgt = TimeZone(identifier: "Asia/Singapore")!
let expiredInfo = ExpiryInfo(expired: true, expiresAt: "2026-11-03T04:00:00.000Z", daysLeft: nil)
check(ExpiryDisplay.expiredText(expiredInfo, timeZone: utc) == "Expired \u{00B7} 3 Nov 2026", "Expired · 3 Nov 2026")
check(ExpiryDisplay.expiredText(ExpiryInfo(expired: true, expiresAt: nil, daysLeft: nil), timeZone: utc) == "Expired", "expired without a date -> just Expired")
check(ExpiryDisplay.expiredText(ExpiryInfo(expired: false, expiresAt: "2026-11-03T04:00:00Z", daysLeft: 3), timeZone: utc) == nil, "not expired -> no Expired text")
check(ExpiryDisplay.expiredText(ExpiryInfo(expired: true, expiresAt: "2026-11-03T20:00:00Z", daysLeft: nil), timeZone: sgt) == "Expired \u{00B7} 4 Nov 2026",
      "the date is shown in the device's time zone")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: 7)) == "7 days left", "7 days left is shown")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: 8)) == nil, "more than a week left -> nothing")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: 29)) == nil, "29 days left -> nothing")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: 1)) == "1 day left", "1 day left")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: 0)) == "0 days left", "0 days left")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: false, expiresAt: nil, daysLeft: nil)) == nil, "no daysLeft -> nothing")
check(ExpiryDisplay.daysLeftText(ExpiryInfo(expired: true, expiresAt: nil, daysLeft: 3)) == nil, "expired never shows days left")
check(ExpiryInfo.none.expired == false && ExpiryDisplay.expiredText(.none) == nil && ExpiryDisplay.daysLeftText(.none) == nil, "no expiry info (older backend) shows nothing")
let expirySuite = UserDefaults(suiteName: suiteName + ".expiry")!
check(ExpiryStore.load(expirySuite) == .none, "no stored expiry -> none")
ExpiryStore.save(expiredInfo, to: expirySuite)
check(ExpiryStore.load(expirySuite) == expiredInfo, "expiry survives a cold start")
ExpiryStore.save(.none, to: expirySuite)
check(ExpiryStore.load(expirySuite) == .none, "and clears when the profile says not expired")
expirySuite.removePersistentDomain(forName: suiteName + ".expiry")

// MARK: 17. /profile expiry fields

section("17. /profile: expiry fields are optional and a wrong type never fails the profile")

do {
    let profileHead = #""ok":true,"enabled":true,"profileId":"p","ownerLabel":"x","serverRegion":"Singapore","routingMode":"smart""#
    let expiredProfile = try decode(ProfileResponse.self, "{\(profileHead),\"regions\":[{\"id\":\"singapore\",\"name\":\"Singapore\",\"isDefault\":true}],\"expired\":true,\"expiresAt\":\"2026-10-03T04:00:00.000Z\",\"daysLeft\":0}").status()
    check(expiredProfile.expired && expiredProfile.expiresAt == "2026-10-03T04:00:00.000Z" && expiredProfile.daysLeft == 0, "expired profile decodes")
    check(expiredProfile.regions.map(\.id) == ["singapore"] && expiredProfile.enabled, "expired is still 200 with enabled unchanged and the assigned region")
    let plain = try decode(ProfileResponse.self, "{\(profileHead)}").status()
    check(!plain.expired && plain.expiresAt == nil && plain.daysLeft == nil, "older backend: no expiry")
    let soon = try decode(ProfileResponse.self, "{\(profileHead),\"expired\":false,\"expiresAt\":\"2026-10-27T04:00:00.000Z\",\"daysLeft\":5}").status()
    check(!soon.expired && soon.daysLeft == 5, "5 days left decodes")
    let nulls = try decode(ProfileResponse.self, "{\(profileHead),\"expired\":null,\"expiresAt\":null,\"daysLeft\":null}").status()
    check(!nulls.expired && nulls.expiresAt == nil && nulls.daysLeft == nil, "null expiry fields")
    let revokedHead = #""ok":true,"enabled":false,"profileId":"p","ownerLabel":"x","serverRegion":"Singapore","routingMode":"smart""#
    let bad = try decode(ProfileResponse.self, "{\(revokedHead),\"expired\":\"yes\",\"expiresAt\":5,\"daysLeft\":\"x\",\"regions\":\"oops\"}").status()
    check(bad.enabled == false && !bad.expired && bad.expiresAt == nil && bad.daysLeft == nil && bad.regions == [.tokyo],
          "wrong-typed expiry fields + regions together: profile still decodes, revoke flag kept")
} catch { check(false, "profile expiry decoding threw: \(error)") }

// MARK: 18. /owner/invites: region + access fields

section("18. /owner/invites: region, duration and expiry per invite (optional)")

let inviteBase = #""code":"RF-A","label":"Alice","maxDevices":3,"activeDevices":1,"monthlyQuotaGB":200,"enabled":true,"expiresAt":null,"createdAt":"2026-06-01 08:00:00""#
do {
    let newInvites = try decode(OwnerInvitesResponse.self, """
    {"ok":true,"invites":[
     {\(inviteBase),"region":"singapore","durationDays":30,"activatedAt":"2026-10-22T01:00:00.000Z","effectiveExpiresAt":"2026-11-21T01:00:00.000Z","daysLeft":29,"expired":false},
     {"code":"RF-B","label":"Ben","maxDevices":1,"activeDevices":0,"monthlyQuotaGB":200,"enabled":true,"createdAt":"x","region":"tokyo","durationDays":null,"activatedAt":null,"effectiveExpiresAt":null,"daysLeft":null,"expired":false}
    ]}
    """)
    check(newInvites.invites?.count == 2, "both invites decode")
    let a = newInvites.access["RF-A"]
    check(a?.region == "singapore" && a?.durationDays == 30 && a?.daysLeft == 29 && a?.expired == false, "access fields decode")
    check(InviteStatusLine.status(a, timeZone: utc) == InviteStatus(text: "Expires 21 Nov 2026 \u{00B7} 29 days left", tone: .neutral),
          "status line: Expires 21 Nov 2026 · 29 days left")
    check(newInvites.access["RF-B"]?.isPresent == true && InviteStatusLine.status(newInvites.access["RF-B"]) == nil, "no limit -> region only, no status line")
    let oldInvites = try decode(OwnerInvitesResponse.self, #"{"ok":true,"invites":[{\#(inviteBase)}]}"#)
    check(oldInvites.invites?.count == 1 && oldInvites.access.isEmpty, "older backend: list decodes, no access info (controls stay hidden)")
    let brokenInvites = try decode(OwnerInvitesResponse.self, """
    {"ok":true,"invites":[{\(inviteBase),"region":5,"durationDays":"x","activatedAt":false,"effectiveExpiresAt":[],"daysLeft":"?","expired":"no"},
                          {\(inviteBase.replacingOccurrences(of: "RF-A", with: "RF-C")),"region":"tokyo","expired":false}]}
    """)
    check(brokenInvites.invites?.count == 2, "wrong-typed access fields never break the invite list")
    check(brokenInvites.access["RF-A"] == nil && brokenInvites.access["RF-C"]?.region == "tokyo", "an invite whose fields are all unusable has no access info; another one keeps its own")
} catch { check(false, "owner invites decoding threw: \(error)") }

section("19. invite status line")

func status(_ access: InviteAccess?) -> InviteStatus? { InviteStatusLine.status(access, timeZone: utc) }
check(status(InviteAccess(durationDays: 30, effectiveExpiresAt: "2026-10-20T01:00:00.000Z", expired: true)) == InviteStatus(text: "Expired 20 Oct 2026", tone: .danger),
      "Expired 20 Oct 2026 (red)")
check(status(InviteAccess(durationDays: 30, expired: true))?.text == "Expired", "expired without a date")
check(status(InviteAccess(region: "singapore", durationDays: 60, expired: false)) == InviteStatus(text: "Starts on activation", tone: .neutral),
      "duration set, not activated yet -> Starts on activation")
check(status(InviteAccess(durationDays: 90, effectiveExpiresAt: "2026-10-28T01:00:00.000Z", daysLeft: 6, expired: false))
      == InviteStatus(text: "Expires 28 Oct 2026 \u{00B7} 6 days left", tone: .warning), "6 days left is flagged")
check(status(InviteAccess(effectiveExpiresAt: "2026-12-30T01:00:00.000Z", daysLeft: 69, expired: false))?.tone == .neutral, "69 days left is calm")
check(status(InviteAccess(region: "tokyo", expired: false)) == nil, "no limit -> no line")
check(status(nil) == nil, "no access info -> no line")
check(status(InviteAccess(effectiveExpiresAt: "2026-10-28T01:00:00.000Z", expired: false))?.text == "Expires 28 Oct 2026", "no daysLeft -> date only")
check(status(InviteAccess(effectiveExpiresAt: "2026-10-28T01:00:00.000Z", daysLeft: 1, expired: false))?.text == "Expires 28 Oct 2026 \u{00B7} 1 day left", "1 day left")

// MARK: 20. choices and update payload

section("20. access choice + update/create payloads (only changed fields)")

check(AccessChoice(durationDays: nil) == AccessChoice(preset: .noLimit) && AccessChoice(durationDays: nil).durationDays == nil, "no limit")
check([7, 30, 90, 180, 365].map { AccessChoice(durationDays: $0).preset } == [.d7, .d30, .d90, .d180, .d365], "preset durations map to presets")
check(AccessChoice(durationDays: 45).preset == .custom && AccessChoice(durationDays: 45).durationDays == 45, "other durations are Custom")
check(AccessChoice(durationDays: 99999).durationDays == 3650 && AccessChoice(durationDays: 0).durationDays == 1, "Custom is clamped to 1...3650")
check(AccessChoice(preset: .custom, customDays: 0).durationDays == 1 && AccessChoice(preset: .custom, customDays: 5000).durationDays == 3650, "typed days are clamped")
var typed = AccessChoice(preset: .custom, customDays: 45)
typed.customDays = -3
check(typed.durationDays == 1, "days typed later are clamped too")
check(AccessChoice(preset: .d30).durationDays == 30 && AccessChoice(preset: .noLimit).summary == "No limit" && AccessChoice(preset: .d90).summary == "90 days", "summary")
check(AccessPreset.allCases.map(\.label) == ["No limit", "7 days", "30 days", "90 days", "180 days", "365 days", "Custom"], "the menu offers exactly these choices")

let originalInvite = try! JSONDecoder().decode(OwnerInvite.self, from: Data("{\(inviteBase)}".utf8))
let accessNow = InviteAccess(region: "tokyo", durationDays: 30, activatedAt: "2026-10-01T00:00:00Z", effectiveExpiresAt: "2026-10-31T00:00:00Z", daysLeft: 9, expired: false)
func edit(region: String? = "tokyo", access: AccessChoice? = AccessChoice(durationDays: 30)) -> InviteEdit {
    InviteEdit(code: "RF-A", label: "Alice", maxDevices: 3, monthlyQuotaGB: 200, enabled: true, region: region, access: access)
}
let baseKeys: Set<String> = ["code", "newCode", "label", "maxDevices", "monthlyQuotaGB", "enabled"]
check(Set(InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit()).keys) == baseKeys, "nothing changed -> neither region nor durationDays is sent")
let regionOnly = InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(region: "singapore"))
check(Set(regionOnly.keys) == baseKeys.union(["region"]) && regionOnly["region"] == .string("singapore"), "region changed -> only region is added")
let durationOnly = InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(access: AccessChoice(durationDays: 90)))
check(Set(durationOnly.keys) == baseKeys.union(["durationDays"]) && durationOnly["durationDays"] == .int(90), "duration changed -> only durationDays is added")
let cleared = InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(access: AccessChoice(preset: .noLimit)))
check(cleared["durationDays"] == JSONValue.null && cleared["region"] == nil, "No limit clears the duration with an explicit null")
let both2 = InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(region: "singapore", access: AccessChoice(preset: .custom, customDays: 45)))
check(both2["region"] == .string("singapore") && both2["durationDays"] == .int(45), "both changed -> both sent")
check(Set(InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(region: "TOKYO")).keys) == baseKeys, "region compared case-insensitively")
check(Set(InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(region: nil, access: nil)).keys) == baseKeys, "controls hidden (owner invite, Apple Review) -> nothing extra")
check(Set(InviteBody.update(original: originalInvite, originalAccess: accessNow, edit: edit(region: "singapore", access: nil)).keys) == baseKeys.union(["region"]),
      "Apple Review: region only, never durationDays")
check(Set(InviteBody.update(original: originalInvite, originalAccess: nil, edit: edit(region: "singapore", access: AccessChoice(durationDays: 90))).keys) == baseKeys,
      "older backend (no access info): the new fields are never sent")
let neverLimited = InviteAccess(region: "tokyo", expired: false)
check(Set(InviteBody.update(original: originalInvite, originalAccess: neverLimited, edit: edit(access: AccessChoice(preset: .noLimit))).keys) == baseKeys,
      "no limit before and after -> nothing sent")
if let json = try? JSONEncoder().encode(cleared),
   let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
    check(object["durationDays"] is NSNull && object["code"] as? String == "RF-A" && object["enabled"] as? Bool == true,
          "the null really is JSON null on the wire")
} else { check(false, "update body did not encode") }
let created = InviteBody.create(code: "RF-NEW", label: nil, maxDevices: 1, monthlyQuotaGB: 200, region: "tokyo", access: AccessChoice(preset: .noLimit))
check(Set(created.keys) == ["code", "maxDevices", "monthlyQuotaGB"], "create: Tokyo + no limit + no label sends only the base fields")
let createdSg = InviteBody.create(code: "RF-NEW", label: "Zed", maxDevices: 2, monthlyQuotaGB: 100, region: "singapore", access: AccessChoice(durationDays: 30))
check(createdSg["region"] == .string("singapore") && createdSg["durationDays"] == .int(30) && createdSg["label"] == .string("Zed"), "create: Singapore + 30 days")
check(InviteBody.create(code: "C", label: nil, maxDevices: 1, monthlyQuotaGB: 1, region: nil, access: nil).keys.contains("region") == false, "create: controls hidden -> nothing extra")
check(InviteRegionOptions.options(ownerRegions: [.tokyo], current: nil).map(\.id) == ["tokyo"], "owner without Singapore: only Tokyo can be assigned")
check(InviteRegionOptions.options(ownerRegions: both, current: nil).map(\.id) == ["tokyo", "singapore"], "owner with Singapore: both")
check(InviteRegionOptions.options(ownerRegions: [.tokyo], current: "singapore").map(\.id) == ["tokyo", "singapore"], "an invite already on Singapore still shows it")
check(InviteRegionOptions.options(ownerRegions: both, current: "SINGAPORE").map(\.id) == ["tokyo", "singapore"], "current region matched case-insensitively")

// MARK: 21. SPEC3: last use per device

section("21. lastUsedAt: present / null / absent / malformed")

let spec3Now = Date(timeIntervalSince1970: 1_800_000_000)
let isoFormatter = ISO8601DateFormatter()
func ago(_ seconds: TimeInterval) -> String { isoFormatter.string(from: spec3Now.addingTimeInterval(-seconds)) }

func dev(_ id: String, _ label: String, used: Double, last: String?, includeLast: Bool = true,
         enabled: Bool = true, online: Bool = false) -> String {
    var extra = ",\"usage\":{\"usedGB\":\(used),\"quotaGB\":200,\"percent\":null}"
    if includeLast { extra += last.map { ",\"lastUsedAt\":\"\($0)\"" } ?? ",\"lastUsedAt\":null" }
    if online { extra += ",\"online\":true" }
    return device(id, label: label, name: "dev-" + id, model: "M", app: "1", enabled: enabled)
        .replacingOccurrences(of: "__USAGE__", with: extra)
}

do {
    let r = try decode(OwnerDevicesResponse.self, "{\"ok\":true,\"devices\":[" + [
        dev("p1", "P", used: 1, last: "2026-10-22T06:00:00.000Z"),
        dev("p2", "P", used: 1, last: nil),
        dev("p3", "P", used: 1, last: nil, includeLast: false),
    ].joined(separator: ",") + "]}")
    check(r.lastUsed["p1"]?.date == ISODate.parse("2026-10-22T06:00:00.000Z") && r.lastUsed["p1"]?.date != nil, "lastUsedAt decodes to a date")
    check(r.lastUsed["p2"] == DeviceLastUsed(iso: nil), "null = reported, never used")
    check(r.lastUsed["p3"] == nil, "absent = the backend does not say")
    check(r.devices?.count == 3 && r.usage.count == 3, "the device list and usage are unaffected")
    let malformed = try decode(OwnerDevicesResponse.self, "{\"ok\":true,\"devices\":["
        + device("m1", label: "M", name: "m", model: nil, app: nil).replacingOccurrences(of: "__USAGE__", with: ",\"usage\":{\"usedGB\":3},\"lastUsedAt\":12345")
        + "]}")
    check(malformed.devices?.count == 1 && malformed.lastUsed["m1"] == nil && malformed.usage["m1"]?.usedGB == 3,
          "a wrong-typed lastUsedAt is read as 'not reported' (not as Never) and breaks nothing")
    let oldBackend = try decode(OwnerDevicesResponse.self, oldDevices)
    check(oldBackend.lastUsed.isEmpty, "older backend: no lastUsedAt at all")
} catch { check(false, "lastUsedAt decoding threw: \(error)") }
check(ISODate.parse("2026-10-22 08:30:00") == ISODate.parse("2026-10-22T08:30:00Z"), "the server's other timestamp style (UTC) parses too")

section("22. users list: sort, grouping, online, last used")

do {
    let r = try decode(OwnerDevicesResponse.self, "{\"ok\":true,\"devices\":[" + [
        dev("a1", "Alpha", used: 100, last: ago(7_200)),
        dev("a2", "Alpha", used: 50, last: ago(60), online: true),
        dev("b1", "Bravo", used: 100, last: ago(5 * 86_400)),
        dev("b2", "Bravo", used: 50, last: ago(86_400), enabled: false, online: true),
        dev("c1", "Charlie", used: 150, last: nil),
        dev("d1", "Delta", used: 200, last: ago(10 * 86_400)),
        dev("e1", "Echo", used: 0, last: nil),
        dev("f1", "Foxtrot", used: 0, last: nil),
        dev("g1", "Golf", used: 10, last: ago(100)),
        dev("g2", "Golf", used: 5, last: nil).replacingOccurrences(of: "CODE-Golf", with: "CODE-Golf2"),
    ].joined(separator: ",") + "]}")
    let users = UsageMetrics.groups(devices: r.devices ?? [], usage: r.usage, lastUsed: r.lastUsed)
    check(users.map(\.label) == ["Delta", "Alpha", "Bravo", "Charlie", "Golf", "Echo", "Foxtrot"],
          "users by total used desc; equal totals: most recent last use first, never-used last; then by name: \(users.map(\.label))")
    let alpha = users.first(where: { $0.label == "Alpha" })!
    check(alpha.totalGB == 150 && alpha.online && alpha.devicesText == "2 devices", "Alpha: total 150, online, 2 devices")
    check(alpha.lastUsedAt == ISODate.parse(ago(60)), "user's last use = the most recent of its devices")
    let bravo = users.first(where: { $0.label == "Bravo" })!
    check(bravo.totalGB == 150, "a signed-out device's usage still counts in the total")
    check(bravo.activeDevices == 1 && bravo.devicesText == "1 device", "signed-out devices are not counted as active")
    check(!bravo.online, "a signed-out device never makes the user online")
    check(bravo.rows.first(where: { $0.id == "b2" })?.enabled == false && bravo.rows.first(where: { $0.id == "b2" })?.online == false,
          "the signed-out device row is not online")
    check(bravo.lastUsedAt == ISODate.parse(ago(86_400)), "last use still includes the signed-out device")
    let charlie = users.first(where: { $0.label == "Charlie" })!
    check(charlie.lastUsedAt == nil && charlie.lastUsedReported, "never used but the backend reports it")
    let golf = users.first(where: { $0.label == "Golf" })!
    check(golf.inviteCodes == ["CODE-Golf", "CODE-Golf2"], "distinct invite codes, sorted")
    check(users.first(where: { $0.label == "Alpha" })?.inviteCodes == ["CODE-Alpha"], "one invite code for a user with one invite")
    let unreported = UsageMetrics.groups(devices: r.devices ?? [], usage: r.usage)
    check(unreported.allSatisfy { !$0.lastUsedReported } && unreported.map(\.label).first == "Delta", "no lastUsedAt from the backend: not reported, order by usage")
    check(unreported.allSatisfy { g in
        ActivityText.text(online: g.online, lastUsedAt: g.lastUsedAt, reported: g.lastUsedReported, now: spec3Now).map { $0 == "Online" } ?? true
    }, "not reported: no 'Last used' / 'Never' text (only Online may show)")
    check(UsageMetrics.ranksBefore(users[0], users[1]) && !UsageMetrics.ranksBefore(users[1], users[0]), "ranksBefore is a strict order")
} catch { check(false, "users list decoding threw: \(error)") }

section("23. relative time + activity text")

func rel(_ seconds: TimeInterval) -> String { RelativeTime.text(from: spec3Now.addingTimeInterval(-seconds), now: spec3Now, timeZone: utc) }
check(rel(0) == "just now" && rel(59) == "just now", "under a minute -> just now")
check(rel(60) == "1m ago" && rel(3_599) == "59m ago", "minutes")
check(rel(3_600) == "1h ago" && rel(7_200) == "2h ago" && rel(86_399) == "23h ago", "hours (2h ago)")
check(rel(86_400) == "1d ago" && rel(29 * 86_400) == "29d ago", "days")
check(rel(30 * 86_400) == ISODate.dayText(date: spec3Now.addingTimeInterval(-30 * 86_400), timeZone: utc) && !rel(30 * 86_400).hasSuffix("ago"),
      "a month or more -> a date")
check(RelativeTime.text(from: spec3Now.addingTimeInterval(500), now: spec3Now, timeZone: utc) == "just now", "a time in the future (clock skew) -> just now")
check(ActivityText.text(online: true, lastUsedAt: nil, reported: false, now: spec3Now) == "Online", "online wins")
check(ActivityText.text(online: false, lastUsedAt: spec3Now.addingTimeInterval(-7_200), reported: true, now: spec3Now, timeZone: utc) == "Last used 2h ago", "Last used 2h ago")
check(ActivityText.text(online: false, lastUsedAt: nil, reported: true, now: spec3Now) == "Never", "null -> Never")
check(ActivityText.text(online: false, lastUsedAt: nil, reported: false, now: spec3Now) == nil, "not reported -> nothing")
check(ActivityText.text(online: false, lastUsedAt: spec3Now, reported: false, now: spec3Now) == nil, "not reported -> nothing even with a date")

section("24. log out: fallback for a backend without POST /owner/users/logout, texts, landing notice")

check(LogoutPlan.needsFallback(APIError.status(404, "Cannot POST /owner/users/logout")), "404 -> fall back to per-device revoke")
check(!LogoutPlan.needsFallback(APIError.status(403, "owner invite cannot be logged out")), "403 (owner invite) is a real refusal, no fallback")
check(!LogoutPlan.needsFallback(APIError.status(500, "")) && !LogoutPlan.needsFallback(APIError.status(401, "")), "5xx / 401 -> no fallback")
check(!LogoutPlan.needsFallback(APIError.invalidURL) && !LogoutPlan.needsFallback(APIError.transport(URLError(.notConnectedToInternet))), "other errors -> no fallback")
do {
    let r = try decode(OwnerDevicesResponse.self, "{\"ok\":true,\"devices\":[" + [
        dev("x1", "Xan", used: 1, last: nil),
        dev("x2", "Xan", used: 1, last: nil, enabled: false),
        dev("y1", "Yan", used: 1, last: nil),
        dev("z1", "Zed", used: 1, last: nil),
    ].joined(separator: ",") + "]}")
    let targets = LogoutPlan.fallbackTargets(devices: r.devices ?? [], codes: ["CODE-Xan"])
    check(targets.map(\.profileId) == ["x1"], "fallback signs out only the enabled devices of that invite")
    check(LogoutPlan.fallbackTargets(devices: r.devices ?? [], codes: ["CODE-Xan", "CODE-Yan"]).map(\.profileId).sorted() == ["x1", "y1"],
          "a user with several invites: all of them")
    check(LogoutPlan.fallbackTargets(devices: r.devices ?? [], codes: ["CODE-Nobody"]).isEmpty, "unknown invite -> nothing to do")
} catch { check(false, "fallback targets decoding threw: \(error)") }
check(LogoutPlan.deviceTitle("Alice iPhone") == "Log out Alice iPhone?" && LogoutPlan.deviceMessage == "It will need the invite code to reconnect.",
      "device confirmation text")
check(LogoutPlan.allTitle(count: 3, label: "Alice") == "Log out all 3 devices of Alice?" && LogoutPlan.allTitle(count: 1, label: "Ben") == "Log out 1 device of Ben?",
      "log out all confirmation text")
check(SignedOut.notice == "Signed out. Enter your invite code to reconnect.", "landing notice text")

suite.removePersistentDomain(forName: suiteName)
print("\n\(checks - failures)/\(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
exit(failures == 0 ? 0 : 1)
