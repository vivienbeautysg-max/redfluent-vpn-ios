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

    func updateInvite(_ invite: OwnerInvite, label: String, maxDevices: Int, monthlyQuotaGB: Int, enabled: Bool, token: String) async {
        do {
            let updated = try await api.updateOwnerInvite(
                invite,
                label: label,
                maxDevices: maxDevices,
                monthlyQuotaGB: monthlyQuotaGB,
                enabled: enabled,
                token: token
            )
            if let idx = invites.firstIndex(where: { $0.code == updated.code }) {
                invites[idx] = updated
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
                EditInviteView(invite: invite) { label, maxDevices, monthlyQuotaGB, enabled in
                    guard let token = appState.currentProfile?.token else { return }
                    await model.updateInvite(
                        invite,
                        label: label,
                        maxDevices: maxDevices,
                        monthlyQuotaGB: monthlyQuotaGB,
                        enabled: enabled,
                        token: token
                    )
                }
            }
            .sheet(item: $deviceToRename) { device in
                RenameDeviceView(device: device) { name in
                    guard let token = appState.currentProfile?.token else { return }
                    await model.renameDevice(device, displayName: name, token: token)
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
    let onSave: (String, Int, Int, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var maxDevices: Int
    @State private var monthlyQuotaGB: Int
    @State private var enabled: Bool
    @State private var isSaving = false

    init(invite: OwnerInvite, onSave: @escaping (String, Int, Int, Bool) async -> Void) {
        self.invite = invite
        self.onSave = onSave
        _label = State(initialValue: invite.label)
        _maxDevices = State(initialValue: invite.maxDevices)
        _monthlyQuotaGB = State(initialValue: invite.monthlyQuotaGB ?? 200)
        _enabled = State(initialValue: invite.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite") {
                    LabeledContent("Code", value: invite.code)
                    TextField("Label", text: $label)
                    Stepper("Device limit: \(maxDevices)", value: $maxDevices, in: 1...100)
                    Stepper("Monthly limit: \(monthlyQuotaGB) GB", value: $monthlyQuotaGB, in: 1...2000, step: 50)
                    Toggle("Enabled", isOn: $enabled)
                }
            }
            .navigationTitle("Edit Invite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSaving = true
                        Task {
                            await onSave(label, maxDevices, monthlyQuotaGB, enabled)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RenameDeviceView: View {
    let device: OwnerDevice
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var isSaving = false

    init(device: OwnerDevice, onSave: @escaping (String) async -> Void) {
        self.device = device
        self.onSave = onSave
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
            }
            .navigationTitle("Rename Device")
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
}

#Preview {
    OwnerAdminView()
        .environmentObject(AppState())
}
