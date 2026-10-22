import SwiftUI
import UIKit

@MainActor
final class OwnerAdminViewModel: ObservableObject {
    @Published var invites: [OwnerInvite] = []
    /// Region / access duration / expiry per invite code (1.2 backends); empty on an older one.
    @Published var inviteAccess: [String: InviteAccess] = [:]
    @Published var devices: [OwnerDevice] = []
    /// Current-period usage by profileId; empty when the backend has no usage data.
    @Published var usage: [String: DeviceUsage] = [:]
    @Published var usagePeriod: UsagePeriod?
    @Published var activationEvents: [OwnerActivationEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func refresh(token: String) async {
        #if DEBUG
        if ScreenshotMode.isOn {
            invites = ScreenshotMode.ownerInvites
            inviteAccess = ScreenshotMode.ownerInviteAccess
            devices = ScreenshotMode.ownerDevices
            usage = ScreenshotMode.hidesUsage ? [:] : ScreenshotMode.ownerUsage
            usagePeriod = ScreenshotMode.ownerPeriod
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
            activationEvents = try await activationList
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Saves an invite change. nil on success, otherwise the server's reason (shown inside the sheet).
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

    func deleteInvite(_ invite: OwnerInvite, token: String) async -> Bool {
        do {
            _ = try await api.deleteOwnerInvite(invite, token: token)
            invites.removeAll { $0.code == invite.code }
            devices.removeAll { $0.inviteCode == invite.code }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func renameDevice(_ device: OwnerDevice, displayName: String, token: String) async {
        do {
            let updated = try await api.renameOwnerDevice(
                profileId: device.profileId,
                displayName: displayName,
                token: token
            )
            if let idx = devices.firstIndex(where: { $0.profileId == updated.profileId }) {
                devices[idx] = updated
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokeDevice(_ device: OwnerDevice, token: String) async -> Bool {
        do {
            let updated = try await api.revokeOwnerDevice(profileId: device.profileId, token: token)
            if let idx = devices.firstIndex(where: { $0.profileId == updated.profileId }) {
                devices[idx] = updated
            }
            if let inviteIdx = invites.firstIndex(where: { $0.code == updated.inviteCode }) {
                let invite = invites[inviteIdx]
                invites[inviteIdx] = OwnerInvite(
                    code: invite.code,
                    label: invite.label,
                    maxDevices: invite.maxDevices,
                    activeDevices: max(0, invite.activeDevices - 1),
                    monthlyQuotaGB: invite.monthlyQuotaGB,
                    enabled: invite.enabled,
                    expiresAt: invite.expiresAt,
                    createdAt: invite.createdAt
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct OwnerAdminView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OwnerAdminViewModel()
    @State private var showingCreateInvite = false
    @State private var inviteToEdit: OwnerInvite?
    @State private var deviceToRename: OwnerDevice?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }

                Section {
                    Button { showingCreateInvite = true } label: {
                        Label("Create invite", systemImage: "plus.circle.fill")
                    }
                    .font(Theme.Font.bodyLarge)
                    .foregroundStyle(Theme.Color.brandPrimary)
                }

                if !usageGroups.isEmpty {
                    Section(usageHeader) {
                        ForEach(usageGroups) { group in
                            OwnerUsageGroupView(group: group)
                        }
                    }
                }

                Section("Invites") {
                    if model.invites.isEmpty && !model.isLoading {
                        Text("No invites yet")
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ForEach(model.invites) { invite in
                        Button {
                            inviteToEdit = invite
                        } label: {
                            OwnerInviteRow(invite: invite,
                                           access: model.inviteAccess[invite.code],
                                           isOwnerInvite: isOwnerInvite(invite))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Activation Events") {
                    if model.activationEvents.isEmpty && !model.isLoading {
                        Text("No activation attempts recorded yet")
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ForEach(model.activationEvents) { event in
                        OwnerActivationEventRow(event: event)
                    }
                }

                Section(devicesHeader) {
                    if model.devices.isEmpty && !model.isLoading {
                        Text("No activated devices yet")
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ForEach(model.devices) { device in
                        Button {
                            deviceToRename = device
                        } label: {
                            OwnerDeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .navigationTitle("Owner Admin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingCreateInvite, onDismiss: {
                Task { await refresh() }
            }) {
                CreateInviteView()
                    .environmentObject(appState)
            }
            .sheet(item: $inviteToEdit) { invite in
                let access = model.inviteAccess[invite.code]
                EditInviteView(
                    invite: invite,
                    access: access,
                    isOwnerInvite: isOwnerInvite(invite),
                    isReviewInvite: isReviewInvite(invite),
                    regionOptions: InviteRegionOptions.options(ownerRegions: appState.regions, current: access?.region)
                ) { edit in
                    guard let token = appState.currentProfile?.token else { return "Not signed in" }
                    return await model.updateInvite(
                        InviteBody.update(original: invite, originalAccess: access, edit: edit),
                        token: token
                    )
                } onDelete: {
                    guard let token = appState.currentProfile?.token else { return false }
                    return await model.deleteInvite(invite, token: token)
                }
            }

            .sheet(item: $deviceToRename) { device in
                ManageDeviceView(device: device) { name in
                    guard let token = appState.currentProfile?.token else { return }
                    await model.renameDevice(device, displayName: name, token: token)
                } onRevoke: {
                    guard let token = appState.currentProfile?.token else { return false }
                    return await model.revokeDevice(device, token: token)
                }
            }
            .task {
                await refresh()
                #if DEBUG
                if let n = ScreenshotMode.editInviteIndex, model.invites.indices.contains(n - 1) {
                    inviteToEdit = model.invites[n - 1]
                }
                #endif
            }
        }
    }

    /// The owner's own invite: its devices include this one. (The old fixed owner code was rotated away.)
    private var ownerInviteCode: String? {
        model.devices.first(where: { $0.profileId == appState.currentProfile?.profileId })?.inviteCode
    }

    private func isOwnerInvite(_ invite: OwnerInvite) -> Bool {
        invite.code == ownerInviteCode || invite.code == "RF-OWNER-2026"
    }

    private func isReviewInvite(_ invite: OwnerInvite) -> Bool {
        invite.label.trimmingCharacters(in: .whitespaces).lowercased() == "apple review"
    }

    private var usageGroups: [UsageGroup] {
        UsageMetrics.groups(devices: model.devices, usage: model.usage)
    }

    private var usageHeader: String {
        if let since = UsageMetrics.periodText(model.usagePeriod) { return "Usage \u{00B7} \(since)" }
        return "Usage"
    }

    private var devicesHeader: String {
        let n = model.devices.filter { ($0.online ?? $0.inUse) && $0.enabled }.count
        return n > 0 ? "Devices \u{00B7} \(n) online" : "Devices"
    }

    private func refresh() async {
        guard let token = appState.currentProfile?.token else { return }
        await model.refresh(token: token)
    }
}

private struct OwnerActivationEventRow: View {
    let event: OwnerActivationEvent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryCode)
                        .font(Theme.Font.monoBody)
                        .foregroundStyle(Theme.Color.textPrimary)
                    if let matched = event.matchedInviteCode, matched != primaryCode {
                        Text("Matched: \(matched)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
                Spacer()
                Text(event.outcome == "success" ? "Success" : "Failed")
                    .font(Theme.Font.micro)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(statusColor.opacity(0.14))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            Text(reasonSummary)
                .font(Theme.Font.caption)
                .foregroundStyle(statusColor)

            HStack(spacing: Theme.Spacing.md) {
                if let deviceName = event.deviceName, !deviceName.isEmpty {
                    detail("Device", deviceName)
                }
                if let appVersion = event.appVersion, !appVersion.isEmpty {
                    detail("App", appVersion)
                }
                if let active = event.activeDevices, let max = event.maxDevices {
                    detail("Devices", "\(active)/\(max)")
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                if let remoteIp = event.remoteIp, !remoteIp.isEmpty {
                    detail("IP", remoteIp)
                }
                Text(event.createdAtSgt)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var primaryCode: String {
        if let input = event.inviteCodeInput, !input.isEmpty {
            return input
        }
        if let normalized = event.inviteCodeNormalized, !normalized.isEmpty {
            return normalized
        }
        return "Unknown invite"
    }

    private var reasonSummary: String {
        let reason = event.reason ?? "unknown"
        return "HTTP \(event.httpStatus) - \(reason)"
    }

    private var statusColor: Color {
        event.outcome == "success" ? Theme.Color.success : Theme.Color.danger
    }

    private func detail(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
    }
}

private struct OwnerInviteRow: View {
    let invite: OwnerInvite
    let access: InviteAccess?
    let isOwnerInvite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(invite.label)
                    .font(Theme.Font.bodyLarge)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Text(invite.enabled ? "Enabled" : "Disabled")
                    .font(Theme.Font.micro)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background((invite.enabled ? Theme.Color.success : Theme.Color.danger).opacity(0.14))
                    .foregroundStyle(invite.enabled ? Theme.Color.success : Theme.Color.danger)
                    .clipShape(Capsule())
            }
            Text(invite.code)
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: Theme.Spacing.md) {
                metric("Devices", "\(invite.activeDevices)/\(invite.maxDevices)")
                metric("Monthly", invite.monthlyQuotaGB.map { "\($0) GB" } ?? "Unlimited")
                if let region = regionName {
                    metric("Region", region)
                } else {
                    metric("Expires", invite.expiresAt ?? "Never")
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
            if !isOwnerInvite, let status = InviteStatusLine.status(access) {
                Text(status.text)
                    .font(Theme.Font.caption)
                    .foregroundStyle(status.tone.color)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Shown only where the backend reports regions, and not for the owner invite (it uses all of them).
    private var regionName: String? {
        guard !isOwnerInvite, access?.isPresent == true, let region = access?.region else { return nil }
        return region.capitalized
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Font.micro)
            Text(value)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textPrimary)
        }
    }
}

private struct OwnerDeviceRow: View {
    let device: OwnerDevice

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Circle()
                    .fill(isOnline ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                Text(device.displayName)
                    .font(Theme.Font.bodyLarge)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Text(isOnline ? "Online" : statusText)
                    .font(Theme.Font.micro)
                    .foregroundStyle(isOnline ? Theme.Color.success : Theme.Color.textSecondary)
            }
            Text(device.profileId)
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: Theme.Spacing.md) {
                Text(device.inviteLabel ?? device.inviteCode)
                if let appVersion = device.appVersion {
                    Text(appVersion)
                }
                if let conns = device.lastActiveConnections {
                    Text("\(conns) conns")
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var isOnline: Bool { device.online ?? device.inUse }

    private var statusText: String {
        if !device.enabled { return "Revoked" }
        if let last = device.lastHeartbeatAt { return "Seen \(displayServerTime(last))" }
        if let last = device.lastSeenAt { return "Activated \(displayServerTime(last))" }
        return "Inactive"
    }
}

private struct OwnerUsageGroupView: View {
    let group: UsageGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.label)
                    .font(Theme.Font.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(UsageFormat.total(group.totalGB))
                    .font(Theme.Font.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            ForEach(group.rows) { row in
                OwnerUsageDeviceView(row: row)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct OwnerUsageDeviceView: View {
    let row: UsageRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                Text(row.amountText)
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            if let detail = row.detail {
                Text(detail)
                    .font(Theme.Font.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
            if let fraction = row.fraction, let percentText = row.percentText {
                HStack(spacing: Theme.Spacing.sm) {
                    UsageBar(fraction: fraction, color: row.level.color)
                    Text(percentText)
                        .font(Theme.Font.micro)
                        .monospacedDigit()
                        .foregroundStyle(row.level == .critical ? Theme.Color.danger : Theme.Color.textSecondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .opacity(row.enabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

/// Capsule bar drawn directly so track and fill read the same in light and dark mode.
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(geo.size.width * fraction, 6) : 0)
            }
        }
        .frame(height: 8)
    }
}

private extension UsageLevel {
    var color: Color {
        switch self {
        case .ok:       return Theme.Color.success
        case .warning:  return Theme.Color.warning
        case .critical: return Theme.Color.danger
        }
    }
}

private let serverUTCFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private let sgtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Singapore")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'SGT'"
    return formatter
}()

private func displayServerTime(_ raw: String) -> String {
    guard let date = serverUTCFormatter.date(from: raw) else {
        return raw
    }
    return sgtFormatter.string(from: date)
}

private struct EditInviteView: View {
    let invite: OwnerInvite
    let access: InviteAccess?
    let isOwnerInvite: Bool
    let isReviewInvite: Bool
    let regionOptions: [VPNRegion]
    let onSave: (InviteEdit) async -> String?
    let onDelete: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var label: String
    @State private var maxDevices: Int
    @State private var monthlyQuotaGB: Int
    @State private var enabled: Bool
    @State private var region: String
    @State private var accessChoice: AccessChoice
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirm = false
    @State private var saveError: String?

    init(
        invite: OwnerInvite,
        access: InviteAccess?,
        isOwnerInvite: Bool,
        isReviewInvite: Bool,
        regionOptions: [VPNRegion],
        onSave: @escaping (InviteEdit) async -> String?,
        onDelete: @escaping () async -> Bool
    ) {
        self.invite = invite
        self.access = access
        self.isOwnerInvite = isOwnerInvite
        self.isReviewInvite = isReviewInvite
        self.regionOptions = regionOptions
        self.onSave = onSave
        self.onDelete = onDelete
        _code = State(initialValue: invite.code)
        _label = State(initialValue: invite.label)
        _maxDevices = State(initialValue: invite.maxDevices)
        _monthlyQuotaGB = State(initialValue: invite.monthlyQuotaGB ?? 200)
        _enabled = State(initialValue: invite.enabled)
        let current = access?.region ?? RegionPolicy.defaultID
        _region = State(initialValue: regionOptions.first(where: { RegionPolicy.matches($0.id, current) })?.id ?? current)
        _accessChoice = State(initialValue: AccessChoice(durationDays: access?.durationDays))
    }

    /// Region and Access only where the backend reports them, never for the owner invite; the Apple Review
    /// invite takes a region but no duration (the server refuses one).
    private var showsAccessControls: Bool { access?.isPresent == true && !isOwnerInvite }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isOwnerInvite)
                    TextField("Label", text: $label)
                    Stepper("Device limit: \(maxDevices)", value: $maxDevices, in: 1...100)
                    Stepper("Monthly limit: \(monthlyQuotaGB) GB", value: $monthlyQuotaGB, in: 1...2000, step: 50)
                    Toggle("Enabled", isOn: $enabled)
                }
                if showsAccessControls {
                    Section {
                        InviteAccessRows(
                            region: $region,
                            access: $accessChoice,
                            regionOptions: regionOptions,
                            showsAccess: !isReviewInvite,
                            status: isReviewInvite ? nil : InviteStatusLine.status(access)
                        )
                    }
                }
                if isOwnerInvite {
                    Section {
                        Text("The owner invite is protected and cannot be renamed or deleted.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Label("Delete invite", systemImage: "trash")
                            }
                        }
                        .disabled(isDeleting || isSaving)
                    }
                }
                if let saveError {
                    Section {
                        Text(saveError)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.danger)
                    }
                }
            }
            .navigationTitle("Edit Invite")
            .confirmationDialog(
                "Delete invite?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Invite", role: .destructive) {
                    isDeleting = true
                    Task {
                        let ok = await onDelete()
                        isDeleting = false
                        if ok { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the invite from Owner Admin and revokes devices created from it.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || isDeleting || trimmedCode.isEmpty || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        let edit = InviteEdit(
            code: trimmedCode,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            maxDevices: maxDevices,
            monthlyQuotaGB: monthlyQuotaGB,
            enabled: enabled,
            region: showsAccessControls ? region : nil,
            access: showsAccessControls && !isReviewInvite ? accessChoice : nil
        )
        Task {
            let error = await onSave(edit)
            isSaving = false
            if let error { saveError = error } else { dismiss() }
        }
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ManageDeviceView: View {
    let device: OwnerDevice
    let onSave: (String) async -> Void
    let onRevoke: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var isSaving = false
    @State private var isRevoking = false
    @State private var showingRevokeConfirm = false

    init(
        device: OwnerDevice,
        onSave: @escaping (String) async -> Void,
        onRevoke: @escaping () async -> Bool
    ) {
        self.device = device
        self.onSave = onSave
        self.onRevoke = onRevoke
        _displayName = State(initialValue: device.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Display name", text: $displayName)
                    LabeledContent("Profile", value: device.profileId)
                    LabeledContent("Invite", value: device.inviteLabel ?? device.inviteCode)
                    LabeledContent("Status", value: device.inUse ? "In use" : "Not active")
                }
                if isOwnerDevice {
                    Section {
                        Text("Owner devices are protected so you cannot lock yourself out of Owner Admin.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                } else {
                    Section {
                        Button(role: .destructive) {
                            showingRevokeConfirm = true
                        } label: {
                            if isRevoking {
                                ProgressView()
                            } else {
                                Label("Revoke device", systemImage: "xmark.shield")
                            }
                        }
                        .disabled(isSaving || isRevoking || !device.enabled)
                    }
                }
            }
            .navigationTitle("Manage Device")
            .confirmationDialog(
                "Revoke device?",
                isPresented: $showingRevokeConfirm,
                titleVisibility: .visible
            ) {
                Button("Revoke Device", role: .destructive) {
                    isRevoking = true
                    Task {
                        let ok = await onRevoke()
                        isRevoking = false
                        if ok { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This disables VPN access for this device and frees one slot on its invite.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSaving = true
                        Task {
                            await onSave(displayName.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var isOwnerDevice: Bool {
        device.inviteCode == "RF-OWNER-2026"
    }
}

#Preview {
    OwnerAdminView()
        .environmentObject(AppState())
}
