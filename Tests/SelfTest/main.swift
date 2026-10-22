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
    check(old.isOwner == false, "old backend (no isOwner key) -> isOwner false")
    check(old.enabled && old.profileId == "p1" && old.monthlyQuotaGB == 200, "old backend: existing fields unchanged")

    let owner = try decode(ProfileResponse.self, ownerProfile).status()
    check(owner.isOwner, "owner profile: isOwner true")
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

suite.removePersistentDomain(forName: suiteName)
print("\n\(checks - failures)/\(checks) checks passed" + (failures == 0 ? "" : ", \(failures) FAILED"))
exit(failures == 0 ? 0 : 1)
