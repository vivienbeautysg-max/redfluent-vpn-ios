import SwiftUI
import UIKit

@MainActor
final class OwnerAdminViewModel: ObservableObject {
    @Published var invites: [OwnerInvite] = []
    @Published var devices: [OwnerDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func refresh(token: String) async {
        isLoading = true
        errorMessage = nil
        do {
            async let inviteList = api.fetchOwnerInvites(token: token)
            async let deviceList = api.fetchOwnerDevices(token: token)
            invites = try await inviteList
            devices = try await deviceList
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updateInvite(_ invite: OwnerInvite, newCode: String, label: String, maxDevices: Int, monthlyQuotaGB: Int, enabled: Bool, token: String) async -> Bool {
        do {
            let updated = try await api.updateOwnerInvite(
                invite,
                newCode: newCode,
                label: label,
                maxDevices: maxDevices,
                monthlyQuotaGB: monthlyQuotaGB,
                enabled: enabled,
                token: token
            )
            if let idx = invites.firstIndex(where: { $0.code == invite.code || $0.code == updated.code }) {
                invites[idx] = updated
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

                Section("Invites") {
                    if model.invites.isEmpty && !model.isLoading {
                        Text("No invites yet")
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    ForEach(model.invites) { invite in
                        Button {
                            inviteToEdit = invite
                        } label: {
                            OwnerInviteRow(invite: invite)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Devices") {
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
                EditInviteView(invite: invite) { newCode, label, maxDevices, monthlyQuotaGB, enabled in
                    guard let token = appState.currentProfile?.token else { return false }
                    return await model.updateInvite(
                        invite,
                        newCode: newCode,
                        label: label,
                        maxDevices: maxDevices,
                        monthlyQuotaGB: monthlyQuotaGB,
                        enabled: enabled,
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
            .task { await refresh() }
        }
    }

    private func refresh() async {
        guard let token = appState.currentProfile?.token else { return }
        await model.refresh(token: token)
    }
}

private struct OwnerInviteRow: View {
    let invite: OwnerInvite

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
                metric("Expires", invite.expiresAt ?? "Never")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
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
                    .fill(device.inUse ? Theme.Color.success : Theme.Color.textSecondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                Text(device.displayName)
                    .font(Theme.Font.bodyLarge)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                Text(device.inUse ? "In use" : statusText)
                    .font(Theme.Font.micro)
                    .foregroundStyle(device.inUse ? Theme.Color.success : Theme.Color.textSecondary)
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

    private var statusText: String {
        if !device.enabled { return "Revoked" }
        if let last = device.lastHeartbeatAt { return "Seen \(last)" }
        if let last = device.lastSeenAt { return "Activated \(last)" }
        return "Inactive"
    }
}

private struct EditInviteView: View {
    let invite: OwnerInvite
    let onSave: (String, String, Int, Int, Bool) async -> Bool
    let onDelete: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var label: String
    @State private var maxDevices: Int
    @State private var monthlyQuotaGB: Int
    @State private var enabled: Bool
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirm = false

    init(
        invite: OwnerInvite,
        onSave: @escaping (String, String, Int, Int, Bool) async -> Bool,
        onDelete: @escaping () async -> Bool
    ) {
        self.invite = invite
        self.onSave = onSave
        self.onDelete = onDelete
        _code = State(initialValue: invite.code)
        _label = State(initialValue: invite.label)
        _maxDevices = State(initialValue: invite.maxDevices)
        _monthlyQuotaGB = State(initialValue: invite.monthlyQuotaGB ?? 200)
        _enabled = State(initialValue: invite.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isOwnerRootInvite)
                    TextField("Label", text: $label)
                    Stepper("Device limit: \(maxDevices)", value: $maxDevices, in: 1...100)
                    Stepper("Monthly limit: \(monthlyQuotaGB) GB", value: $monthlyQuotaGB, in: 1...2000, step: 50)
                    Toggle("Enabled", isOn: $enabled)
                }
                if isOwnerRootInvite {
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
                        isSaving = true
                        Task {
                            let ok = await onSave(
                                code.trimmingCharacters(in: .whitespacesAndNewlines),
                                label.trimmingCharacters(in: .whitespacesAndNewlines),
                                maxDevices,
                                monthlyQuotaGB,
                                enabled
                            )
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || isDeleting || trimmedCode.isEmpty || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOwnerRootInvite: Bool {
        invite.code == "RF-OWNER-2026"
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
