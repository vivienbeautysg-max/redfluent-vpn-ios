import SwiftUI

@MainActor
final class OwnerAdminViewModel: ObservableObject {
    @Published var invites: [OwnerInvite] = []
    /// Region / access duration / expiry per invite code (1.2 backends); empty on an older one.
    @Published var inviteAccess: [String: InviteAccess] = [:]
    @Published var devices: [OwnerDevice] = []
    /// Current-period usage by profileId; empty when the backend has no usage data.
    @Published var usage: [String: DeviceUsage] = [:]
    @Published var usagePeriod: UsagePeriod?
    /// lastUsedAt by profileId; empty when the backend does not report it.
    @Published var lastUsed: [String: DeviceLastUsed] = [:]
    @Published var activationEvents: [OwnerActivationEvent] = []
    /// Recently Deleted (GET /owner/invites/deleted). Hidden on a backend without it (404).
    @Published var deleted: [DeletedInvite] = []
    @Published var deletedSupported = false
    @Published var deletedError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// This app's own device: its invite is the owner's (the old fixed owner code was rotated away, but is
    /// still recognised).
    var ownProfileId: String?
    private static let legacyOwnerCode = "RF-OWNER-2026"

    private let api = APIClient.shared

    var ownerCodes: Set<String> {
        var codes: Set<String> = [Self.legacyOwnerCode]
        if let own = devices.first(where: { $0.profileId == ownProfileId })?.inviteCode { codes.insert(own) }
        return codes
    }

    var people: [Person] {
        PeopleDirectory.people(invites: invites, access: inviteAccess, devices: devices, usage: usage,
                               lastUsed: lastUsed, ownerCodes: ownerCodes)
    }

    func person(code: String) -> Person? { people.first { $0.code == code } }

    func refresh(token: String) async {
        #if DEBUG
        if ScreenshotMode.isOn {
            invites = ScreenshotMode.ownerInvites
            inviteAccess = ScreenshotMode.ownerInviteAccess
            devices = ScreenshotMode.ownerDevices
            usage = ScreenshotMode.ownerUsage
            usagePeriod = ScreenshotMode.ownerPeriod
            lastUsed = ScreenshotMode.ownerLastUsed()
            activationEvents = ScreenshotMode.ownerEvents
            deleted = ScreenshotMode.ownerDeleted()
            deletedSupported = true
            return
        }
        #endif
        isLoading = true
        errorMessage = nil
        do {
            async let inviteList = api.fetchOwnerInvites(token: token)
            async let deviceList = api.fetchOwnerDevices(token: token)
            async let activationList = api.fetchOwnerActivationEvents(token: token)
            let ownerInvites = try await inviteList
            invites = ownerInvites.invites
            inviteAccess = ownerInvites.access
            let ownerDevices = try await deviceList
            devices = ownerDevices.devices
            usage = ownerDevices.usage
            usagePeriod = ownerDevices.period
            lastUsed = ownerDevices.lastUsed
            activationEvents = try await activationList
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshDeleted(token: token)
        isLoading = false
    }

    /// 404 = older backend: the entry stays hidden and nothing is reported. Any other failure keeps the entry and
    /// shows the reason on the Recently Deleted page.
    func refreshDeleted(token: String) async {
        #if DEBUG
        if ScreenshotMode.isOn { return }
        #endif
        do {
            deleted = try await api.fetchDeletedInvites(token: token)
            deletedSupported = true
            deletedError = nil
        } catch where RecentlyDeleted.isUnsupported(error) {
            deletedSupported = false
            deleted = []
            deletedError = nil
        } catch {
            deletedSupported = true
            deletedError = error.localizedDescription
        }
    }

    /// Saves a change. nil on success, otherwise the server's reason.
    func updateInvite(_ body: [String: JSONValue], token: String) async -> String? {
        do {
            _ = try await api.updateOwnerInvite(body: body, token: token)
        } catch {
            return error.localizedDescription
        }
        await refreshInvites(token: token)
        return nil
    }

    private func refreshInvites(token: String) async {
        do {
            let result = try await api.fetchOwnerInvites(token: token)
            invites = result.invites
            inviteAccess = result.access
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshDevices(token: String) async {
        do {
            let result = try await api.fetchOwnerDevices(token: token)
            devices = result.devices
            usage = result.usage
            usagePeriod = result.period
            lastUsed = result.lastUsed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// nil on success, otherwise the reason.
    func deleteInvite(_ invite: OwnerInvite, token: String) async -> String? {
        do {
            _ = try await api.deleteOwnerInvite(invite, token: token)
        } catch {
            return error.localizedDescription
        }
        invites.removeAll { $0.code == invite.code }
        devices.removeAll { $0.inviteCode == invite.code }
        await refreshDeleted(token: token)
        return nil
    }

    /// nil on success, otherwise what to say (404 / 409 / 403 have their own short texts).
    func restore(_ invite: DeletedInvite, token: String) async -> String? {
        do {
            try await api.restoreInvite(code: invite.code, token: token)
        } catch {
            return RecentlyDeleted.restoreMessage(error)
        }
        await refreshInvites(token: token)
        await refreshDevices(token: token)
        await refreshDeleted(token: token)
        return nil
    }

    func renameDevice(_ device: OwnerDevice, displayName: String, token: String) async -> String? {
        do {
            _ = try await api.renameOwnerDevice(profileId: device.profileId, displayName: displayName, token: token)
        } catch {
            return error.localizedDescription
        }
        await refreshDevices(token: token)
        return nil
    }

    func revokeDevice(_ device: OwnerDevice, token: String) async -> String? {
        do {
            _ = try await api.revokeOwnerDevice(profileId: device.profileId, token: token)
        } catch {
            return error.localizedDescription
        }
        await refreshDevices(token: token)
        await refreshInvites(token: token)
        return nil
    }

    /// Signs out every device of an invite (the invite stays valid). Uses POST /owner/users/logout; a backend
    /// without it answers 404, and then each enabled device is signed out with the per-device revoke.
    /// nil when everything worked, otherwise the (last) reason.
    func logOutAll(code: String, token: String) async -> String? {
        var failure: String?
        do {
            _ = try await api.logoutOwnerUser(code: code, token: token)
        } catch where LogoutPlan.needsFallback(error) {
            for device in LogoutPlan.fallbackTargets(devices: devices, codes: [code]) {
                do {
                    _ = try await api.revokeOwnerDevice(profileId: device.profileId, token: token)
                } catch {
                    failure = error.localizedDescription
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        await refreshDevices(token: token)
        await refreshInvites(token: token)
        return failure
    }
}

enum AdminRoute: Hashable {
    case person(String)
    case deleted
}

private enum AdminTab: String, CaseIterable, Identifiable {
    case people = "People", events = "Events"
    var id: String { rawValue }
}

struct OwnerAdminView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OwnerAdminViewModel()
    @State private var tab: AdminTab = .people
    @State private var path: [AdminRoute] = []
    @State private var showingCreateInvite = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BarRow(title: "Owner Admin") {
                        BarButton(title: "Done", bold: true) { dismiss() }
                    } trailing: {
                        HStack(spacing: 20) {
                            iconButton("arrow.clockwise", label: "Refresh") { Task { await refresh() } }
                            iconButton("plus", label: "New invite") { showingCreateInvite = true }
                        }
                    }
                    header
                    tabs
                    if let error = model.errorMessage {
                        Text(error)
                            .font(Theme.Font.text(13, .medium))
                            .foregroundStyle(Theme.Color.red)
                            .padding(.top, 12)
                    }
                    switch tab {
                    case .people: peopleList
                    case .events: eventsList
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 28)
            }
            .refreshable { await refresh() }
            .overlay {
                if model.isLoading && model.invites.isEmpty {
                    ProgressView().controlSize(.large).tint(Theme.Color.stone)
                }
            }
            .rfPage()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AdminRoute.self) { route in
                switch route {
                case .person(let code):
                    PersonView(code: code, model: model)
                        .environmentObject(appState)
                case .deleted:
                    RecentlyDeletedView(model: model)
                        .environmentObject(appState)
                }
            }
        }
        .sheet(isPresented: $showingCreateInvite, onDismiss: { Task { await refresh() } }) {
            CreateInviteView()
                .environmentObject(appState)
                .rfSheet()
        }
        .task {
            await refresh()
            #if DEBUG
            if ScreenshotMode.opensEvents { tab = .events }
            if let name = ScreenshotMode.openPerson, let person = model.people.first(where: { $0.label == name }) {
                path = [.person(person.code)]
            }
            if ScreenshotMode.opensDeleted { path = [.deleted] }
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            DotTitle(text: tab.rawValue, size: 46, dot: .filled)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                countLine(counts.0, counts.1)
                countLine(counts.2, counts.3)
            }
            .padding(.bottom, 4)
        }
        .padding(.top, 14)
    }

    /// (n, "online", m, "total") for People; (failed, total) for Events.
    private var counts: (Int, String, Int, String) {
        switch tab {
        case .people:
            let people = model.people
            return (people.filter(\.online).count, "online", people.count, "total")
        case .events:
            return (model.activationEvents.filter { $0.outcome != "success" }.count, "failed",
                    model.activationEvents.count, "total")
        }
    }

    private func countLine(_ n: Int, _ word: String) -> some View {
        (Text("\(n) ").font(Theme.Font.text(13, .semibold)).foregroundStyle(Theme.Color.ink)
            + Text(word).font(Theme.Font.text(13, .medium)).foregroundStyle(Theme.Color.stone))
    }

    private var tabs: some View {
        HStack(spacing: 26) {
            ForEach(AdminTab.allCases) { option in
                let on = option == tab
                Button {
                    tab = option
                } label: {
                    Text(option.rawValue)
                        .font(Theme.Font.text(15, on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.Color.ink : Theme.Color.stone)
                        .padding(.bottom, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? Theme.Color.red : .clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 20)
        .overlay(alignment: .bottom) { Rule() }
    }

    // MARK: - People

    @ViewBuilder
    private var peopleList: some View {
        let people = model.people
        let now = Date()
        if people.isEmpty && !model.isLoading {
            Text("No people yet")
                .font(Theme.Font.text(14))
                .foregroundStyle(Theme.Color.stone)
                .padding(.vertical, 18)
        }
        ForEach(people) { person in
            NavigationLink(value: AdminRoute.person(person.code)) {
                PersonRow(person: person, now: now)
            }
            .buttonStyle(.plain)
        }
        if model.deletedSupported {
            NavigationLink(value: AdminRoute.deleted) {
                HStack(spacing: 10) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                    Text("Recently Deleted").font(Theme.Font.text(15, .medium))
                    Spacer()
                    Text("\(model.deleted.count)").font(Theme.Font.text(14))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Color.stone)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { Rule() }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsList: some View {
        if model.activationEvents.isEmpty && !model.isLoading {
            Text("No activation attempts yet")
                .font(Theme.Font.text(14))
                .foregroundStyle(Theme.Color.stone)
                .padding(.vertical, 18)
        }
        ForEach(model.activationEvents) { event in
            ActivationEventRow(event: event)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func refresh() async {
        guard let token = appState.currentProfile?.token else { return }
        model.ownProfileId = appState.currentProfile?.profileId
        await model.refresh(token: token)
    }
}

/// One person: dot (online) · name · used this period; region · devices · last use; Paused / Expired.
private struct PersonRow: View {
    let person: Person
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(person.online ? Theme.Color.red : .clear)
                .overlay(Circle().strokeBorder(person.online ? .clear : Theme.Color.stone, lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(person.label)
                        .font(Theme.Font.text(16.5, .semibold))
                        .foregroundStyle(person.paused ? Theme.Color.stone : Theme.Color.ink)
                        .lineLimit(1)
                    if person.paused { Tag(text: "Paused", color: Theme.Color.stone) }
                    Spacer(minLength: 8)
                    (Text(HomeFormat.gigabytes(person.usedGB)).font(Theme.Font.serif(19))
                        + Text(" GB").font(Theme.Font.text(11, .medium)).foregroundStyle(Theme.Color.stone))
                        .foregroundStyle(Theme.Color.ink)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Text(person.summary(now: now))
                        .font(Theme.Font.text(12.5))
                        .foregroundStyle(Theme.Color.stone)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let status = person.isOwner ? nil : InviteStatusLine.status(person.access) {
                        if status.tone == .danger {
                            Tag(text: "Expired")
                        } else if status.tone == .warning, let left = person.access?.daysLeft {
                            Text(ISODate.daysPhrase(left))
                                .font(Theme.Font.text(12, .semibold))
                                .foregroundStyle(Theme.Color.red)
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivationEventRow: View {
    let event: OwnerActivationEvent

    private var success: Bool { event.outcome == "success" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(primaryCode)
                    .font(Theme.Font.mono(14, medium: true))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                Spacer()
                Tag(text: success ? "Success" : "Failed", color: success ? Theme.Color.stone : Theme.Color.red)
            }
            Text("HTTP \(event.httpStatus) \u{00B7} \(event.reason ?? "unknown")")
                .font(Theme.Font.text(12.5, .medium))
                .foregroundStyle(success ? Theme.Color.stone : Theme.Color.red)
            let details = [event.matchedInviteCode.flatMap { $0 == primaryCode ? nil : "Matched \($0)" },
                           event.deviceName, event.appVersion.map { "v" + $0 },
                           event.activeDevices.flatMap { a in event.maxDevices.map { "\(a)/\($0) devices" } }]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if !details.isEmpty {
                Text(details.joined(separator: " \u{00B7} "))
                    .font(Theme.Font.text(12.5))
                    .foregroundStyle(Theme.Color.stone)
            }
            HStack {
                if let ip = event.remoteIp, !ip.isEmpty {
                    Text(ip).font(Theme.Font.mono(11.5)).foregroundStyle(Theme.Color.stone)
                }
                Spacer()
                Text(event.createdAtSgt).font(Theme.Font.text(12)).foregroundStyle(Theme.Color.stone)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var primaryCode: String {
        if let input = event.inviteCodeInput, !input.isEmpty { return input }
        if let normalized = event.inviteCodeNormalized, !normalized.isEmpty { return normalized }
        return "Unknown invite"
    }
}

#Preview {
    OwnerAdminView()
        .environmentObject(AppState())
}
