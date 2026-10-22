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

suite.removePersistentDomain(forName: suiteName)
print("\n\(checks - failures)/\(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
exit(failures == 0 ? 0 : 1)
