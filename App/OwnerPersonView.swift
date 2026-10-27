import SwiftUI

/// One person (= one invite code): everything about them on one page — usage, devices, settings, actions.
struct PersonView: View {
    @ObservedObject var model: OwnerAdminViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Follows a code change made on this page.
    @State private var code: String
    @State private var draft: PersonDraft?
    @State private var original: PersonDraft?
    @State private var saving = false
    @State private var working = false
    @State private var message: String?
    @State private var confirmingDelete = false
    @State private var confirmingLogOutAll = false
    @State private var deviceForActions: PersonDevice?
    @State private var deviceToLogOut: PersonDevice?
    @State private var deviceToRename: PersonDevice?
    @State private var renameText = ""
    @FocusState private var quotaFocused: Bool

    init(code: String, model: OwnerAdminViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _code = State(initialValue: code)
    }

    private var person: Person? { model.person(code: code) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BarRow {
                        BackButton(title: "People") { dismiss() }
                    } trailing: {
                        if saving {
                            ProgressView().tint(Theme.Color.stone)
                        } else if isDirty {
                            BarButton(title: "Save", bold: true, enabled: pendingEdit != nil) { save() }
                        }
                    }
                    if let person, draft != nil {
                        content(person)
                    } else if person == nil {
                        Text("Not found")
                            .font(Theme.Font.text(15))
                            .foregroundStyle(Theme.Color.stone)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                loadDraft()
                #if DEBUG
                screenshotHooks(proxy)
                #endif
            }
        }
        .rfPage()
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete \(person?.label ?? "")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.deletedSupported ? RecentlyDeleted.deleteMessage : "Its devices will be signed out.")
        }
        .confirmationDialog(LogoutPlan.allTitle(count: person?.devicesInUse ?? 0, label: person?.label ?? ""),
                            isPresented: $confirmingLogOutAll, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { logOutAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LogoutPlan.allMessage)
        }
        .confirmationDialog(deviceForActions?.device.displayName ?? "", isPresented: presence($deviceForActions),
                            titleVisibility: .visible, presenting: deviceForActions) { row in
            Button("Rename") {
                renameText = row.device.displayName
                deviceToRename = row
            }
            if row.signedIn && person?.isOwner == false {
                Button("Log out", role: .destructive) { deviceToLogOut = row }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(LogoutPlan.deviceTitle(deviceToLogOut?.device.displayName ?? ""), isPresented: presence($deviceToLogOut),
                            titleVisibility: .visible, presenting: deviceToLogOut) { row in
            Button("Log out", role: .destructive) { logOut(row) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(LogoutPlan.deviceMessage)
        }
        .alert("Rename device", isPresented: presence($deviceToRename), presenting: deviceToRename) { row in
            TextField("Name", text: $renameText)
            Button("Save") { rename(row) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ person: Person) -> some View {
        let now = Date()
        DotTitle(text: person.label, size: 46, dot: person.online ? .filled : .hollow, lineLimit: 2)
            .padding(.top, 14)
        HStack(spacing: 8) {
            Text(person.summary(now: now))
                .font(Theme.Font.text(14, .medium))
                .foregroundStyle(Theme.Color.stone)
                .lineLimit(2)
            if person.paused { Tag(text: "Paused", color: Theme.Color.stone) }
        }
        .padding(.top, 10)
        if !person.isOwner, let status = InviteStatusLine.status(person.access) {
            Text(status.text)
                .font(Theme.Font.text(13, .medium))
                .foregroundStyle(status.tone.color)
                .padding(.top, 6)
        }

        // This period
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("This period").rfLabelStyle()
                Spacer()
                if let since = UsageMetrics.periodText(model.usagePeriod) {
                    Text(since).font(Theme.Font.text(13, .medium)).foregroundStyle(Theme.Color.ink)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(HomeFormat.gigabytes(person.usedGB))
                    .font(Theme.Font.display(60))
                    .tracking(-0.035 * 60)
                    .foregroundStyle(person.usedGB == nil ? Theme.Color.stone : Theme.Color.ink)
                Text("GB").font(Theme.Font.text(17, .medium)).foregroundStyle(Theme.Color.stone)
            }
            .padding(.top, 10)
        }
        .padding(.top, 24)

        // Devices
        SectionLabel(text: OwnerSectionTitle.counted("Devices", person.devices.count))
            .padding(.top, 28)
            .padding(.bottom, 2)
        Rule()
        if person.devices.isEmpty {
            Text("No devices")
                .font(Theme.Font.text(14))
                .foregroundStyle(Theme.Color.stone)
                .padding(.vertical, 14)
        }
        ForEach(person.devices) { row in
            Button {
                deviceForActions = row
            } label: {
                DeviceRow(row: row, reported: person.lastUsedReported, now: now)
            }
            .buttonStyle(.plain)
        }

        // Settings
        SectionLabel(text: "Settings")
            .padding(.top, 28)
            .padding(.bottom, 2)
        Rule()
        SettingRow(label: "Name") {
            ThemedField(placeholder: "Name", text: field(\.label, ""))
        }
        SettingRow(label: "Code") {
            ThemedField(placeholder: "Code", text: field(\.code, ""), mono: true)
                .disabled(person.isOwner)
                .opacity(person.isOwner ? 0.6 : 1)
        }
        QuotaField(text: field(\.quotaText, ""), focused: $quotaFocused)
            .id("quota")
        SettingRow(label: "Device limit") {
            NumberStepper(value: field(\.maxDevices, 1), range: PersonDraft.deviceLimit)
        }
        if showsAccessControls(person) {
            InviteAccessRows(
                region: field(\.region, RegionPolicy.defaultID),
                access: field(\.access, AccessChoice()),
                regionOptions: regionOptions(person),
                showsAccess: !isReview(person)
            )
        }
        if !person.isOwner {
            SettingRow(label: "Status") {
                SegmentedChoice(options: [(value: true, title: "Active"), (value: false, title: "Paused")],
                                selection: field(\.enabled, true))
            }
        }

        if let message {
            Text(message)
                .font(Theme.Font.text(13, .medium))
                .foregroundStyle(Theme.Color.red)
                .padding(.top, 14)
        }

        // Actions
        if !person.isOwner {
            VStack(spacing: 0) {
                if person.devicesInUse > 0 {
                    actionRow("Log out all devices", systemImage: "rectangle.portrait.and.arrow.right") {
                        confirmingLogOutAll = true
                    }
                }
                actionRow("Delete", systemImage: "trash") { confirmingDelete = true }
            }
            .padding(.top, 28)
            .disabled(working || saving)
        }
    }

    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                Text(title).font(Theme.Font.text(15, .semibold))
                Spacer()
                if working { ProgressView().tint(Theme.Color.stone) }
            }
            .foregroundStyle(Theme.Color.red)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rule() }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Edit state

    private func field<T>(_ keyPath: WritableKeyPath<PersonDraft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { draft?[keyPath: keyPath] ?? fallback }, set: { draft?[keyPath: keyPath] = $0 })
    }

    private var isDirty: Bool { draft != nil && draft != original }

    private func showsAccessControls(_ person: Person) -> Bool { person.access?.isPresent == true && !person.isOwner }

    private func isReview(_ person: Person) -> Bool {
        person.label.trimmingCharacters(in: .whitespaces).lowercased() == "apple review"
    }

    private func regionOptions(_ person: Person) -> [VPNRegion] {
        InviteRegionOptions.options(ownerRegions: appState.regions, current: person.access?.region)
    }

    /// The edit Save would send, or nil while something is invalid.
    private var pendingEdit: InviteEdit? {
        guard let person, let draft else { return nil }
        let access = showsAccessControls(person)
        return draft.edit(showsRegion: access, showsAccess: access && !isReview(person))
    }

    private func loadDraft() {
        guard let person else { return }
        let fresh = PersonDraft(invite: person.invite, access: person.access, regionOptions: regionOptions(person))
        draft = fresh
        original = fresh
    }

    private var token: String? { appState.currentProfile?.token }

    // MARK: - Actions

    private func save() {
        guard let person, let edit = pendingEdit, let token else { return }
        let body = InviteBody.update(original: person.invite, originalAccess: person.access, edit: edit)
        saving = true
        message = nil
        quotaFocused = false
        Task {
            let error = await model.updateInvite(body, token: token)
            saving = false
            if let error {
                message = error
            } else {
                code = edit.code
                loadDraft()
            }
        }
    }

    private func delete() {
        guard let person, let token else { return }
        working = true
        message = nil
        Task {
            let error = await model.deleteInvite(person.invite, token: token)
            working = false
            if let error { message = error } else { dismiss() }
        }
    }

    private func logOutAll() {
        guard let person, let token else { return }
        working = true
        message = nil
        Task {
            message = await model.logOutAll(code: person.code, token: token)
            working = false
        }
    }

    private func logOut(_ row: PersonDevice) {
        guard let token else { return }
        working = true
        message = nil
        Task {
            message = await model.revokeDevice(row.device, token: token)
            working = false
        }
    }

    private func rename(_ row: PersonDevice) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != row.device.displayName, let token else { return }
        Task { message = await model.renameDevice(row.device, displayName: name, token: token) }
    }

    private func presence<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }

    #if DEBUG
    private func screenshotHooks(_ proxy: ScrollViewProxy) {
        guard ScreenshotMode.isOn else { return }
        if let text = ScreenshotMode.editQuota {
            draft?.quotaText = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(nil) { proxy.scrollTo("quota", anchor: .center) }
            }
        }
        if ScreenshotMode.confirmsDelete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { confirmingDelete = true }
        }
    }
    #endif
}

/// A device on the person page: name, use this period, version · last use, and the IPv6 entry it dials.
struct DeviceRow: View {
    let row: PersonDevice
    let reported: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(row.online ? Theme.Color.red : .clear)
                .overlay(Circle().strokeBorder(row.online ? .clear : Theme.Color.stone, lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.device.displayName)
                        .font(Theme.Font.text(16.5, .semibold))
                        .foregroundStyle(Theme.Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    (Text(HomeFormat.gigabytes(row.usedGB)).font(Theme.Font.serif(19))
                        + Text(" GB").font(Theme.Font.text(11, .medium)).foregroundStyle(Theme.Color.stone))
                        .foregroundStyle(Theme.Color.ink)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Text(row.detail(reported: reported, now: now))
                        .font(Theme.Font.text(12.5))
                        .foregroundStyle(Theme.Color.stone)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if row.dedicated { Tag(text: "Dedicated") }
                }
                ipv6Line
            }
        }
        .padding(.vertical, 14)
        .opacity(row.signedIn ? 1 : 0.55)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var ipv6Line: some View {
        switch row.ipv6 {
        case .ipv4Only:
            Text(IPv6Display.ipv4OnlyText)
                .font(Theme.Font.mono(11.5))
                .foregroundStyle(Theme.Color.stone)
        case .address(let prefix, let host):
            (Text(prefix).foregroundStyle(Theme.Color.stone) + Text(host).foregroundStyle(Theme.Color.ink))
                .font(Theme.Font.mono(11.5))
                .tracking(-0.01 * 11.5)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
        }
    }
}

/// People deleted in the last 30 days, each with Restore.
struct RecentlyDeletedView: View {
    @ObservedObject var model: OwnerAdminViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var restoring: Set<String> = []
    @State private var errors: [String: String] = [:]
    @State private var restored: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BarRow {
                    BackButton(title: "People") { dismiss() }
                } trailing: {
                    EmptyView()
                }
                DotTitle(text: "Recently Deleted", size: 46, dot: .filled, lineLimit: 2)
                    .padding(.top, 14)
                if let error = model.deletedError {
                    Text(error)
                        .font(Theme.Font.text(13, .medium))
                        .foregroundStyle(Theme.Color.red)
                        .padding(.top, 12)
                }
                ForEach(restored, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(name) restored").font(Theme.Font.text(14, .semibold)).foregroundStyle(Theme.Color.ink)
                        Text(RecentlyDeleted.restoredNote).font(Theme.Font.text(13, .medium)).foregroundStyle(Theme.Color.red)
                    }
                    .padding(.top, 14)
                }
                Rule().padding(.top, 20)
                if model.deleted.isEmpty {
                    Text("Nothing here")
                        .font(Theme.Font.text(14))
                        .foregroundStyle(Theme.Color.stone)
                        .padding(.vertical, 16)
                }
                let now = Date()
                ForEach(model.deleted) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(item.label)
                                .font(Theme.Font.text(16.5, .semibold))
                                .foregroundStyle(Theme.Color.ink)
                                .lineLimit(1)
                            Spacer()
                            if restoring.contains(item.id) {
                                ProgressView().tint(Theme.Color.stone)
                            } else {
                                Button("Restore") { restore(item) }
                                    .buttonStyle(OutlineButtonStyle())
                            }
                        }
                        Text(RecentlyDeleted.detail(item, now: now))
                            .font(Theme.Font.text(12.5))
                            .foregroundStyle(Theme.Color.stone)
                        if let error = errors[item.id] {
                            Text(error)
                                .font(Theme.Font.text(12.5, .medium))
                                .foregroundStyle(Theme.Color.red)
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .bottom) { Rule() }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .rfPage()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func restore(_ item: DeletedInvite) {
        guard let token = appState.currentProfile?.token else { return }
        restoring.insert(item.id)
        errors[item.id] = nil
        Task {
            let error = await model.restore(item, token: token)
            restoring.remove(item.id)
            if let error { errors[item.id] = error } else { restored.append(item.label) }
        }
    }
}
