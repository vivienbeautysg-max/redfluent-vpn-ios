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
    /// The action running now; its own row shows the spinner.
    @State private var busy: Busy?
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

    private enum Busy: Equatable { case delete, logOutAll, device(String) }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned: Save and its busy state stay in view while the keyboard is up on a field further down.
            BarRow {
                BackButton(title: "People") { dismiss() }
            } trailing: {
                if saving {
                    ProgressView().tint(Theme.Color.stone)
                } else if isDirty {
                    BarButton(title: "Save", bold: true, enabled: pendingEdit != nil && busy == nil) { save() }
                }
            }
            .padding(.horizontal, Theme.gutter)
            scroller
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

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
            .underPinnedBar()
            .onAppear {
                loadDraft()
                #if DEBUG
                screenshotHooks(proxy)
                #endif
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ person: Person) -> some View {
        let now = Date()
        DotTitle(text: person.label, size: 46, dot: person.online ? .filled : .hollow, lineLimit: 2)
            .padding(.top, 14)
            .entrance(0)
        VStack(alignment: .leading, spacing: 0) {
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
        }
        .entrance(1)

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
                    .rollingNumber(person.usedGB)
                Text("GB").font(Theme.Font.text(17, .medium)).foregroundStyle(Theme.Color.stone)
            }
            .padding(.top, 10)
        }
        .padding(.top, 24)
        .entrance(2)

        // Devices
        VStack(alignment: .leading, spacing: 0) {
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
                    DeviceRow(row: row, reported: person.lastUsedReported, now: now, busy: busy == .device(row.id))
                }
                .buttonStyle(RowPressStyle())
                .disabled(busy != nil)
            }
        }
        .entrance(3)

        // Settings
        VStack(alignment: .leading, spacing: 0) {
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
        }
        .entrance(4)

        // Actions
        if !person.isOwner {
            VStack(spacing: 0) {
                if person.devicesInUse > 0 {
                    actionRow("Log out all devices", systemImage: "rectangle.portrait.and.arrow.right", busy: busy == .logOutAll) {
                        confirmingLogOutAll = true
                    }
                }
                actionRow("Delete", systemImage: "trash", busy: busy == .delete) { confirmingDelete = true }
            }
            .padding(.top, 28)
            .disabled(busy != nil || saving)
            .entrance(5)
        }
    }

    private func actionRow(_ title: String, systemImage: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 14, weight: .medium))
                Text(title).font(Theme.Font.text(15, .semibold))
                Spacer()
                if busy { ProgressView().tint(Theme.Color.stone) }
            }
            .foregroundStyle(Theme.Color.red)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { Rule() }
        }
        .buttonStyle(RowPressStyle())
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
        guard !saving, busy == nil else { return }
        saving = true
        model.feedback = nil
        Task {
            // Read the fields only after editing ended: text still being composed is in them now.
            await EditCommit.endEditing()
            guard let person, let token else { saving = false; return }
            guard let edit = pendingEdit else {
                saving = false
                model.feedback = .failure("Not saved: a field is not valid")
                return
            }
            let body = InviteBody.update(original: person.invite, originalAccess: person.access, edit: edit)
            let error = await model.updateInvite(body, token: token)
            saving = false
            if let error {
                model.feedback = .failure(error)
            } else {
                code = edit.code
                loadDraft()
                model.feedback = .success("Saved")
            }
        }
    }

    private func delete() {
        guard busy == nil, let person, let token else { return }
        busy = .delete
        model.feedback = nil
        Task {
            let error = await model.deleteInvite(person.invite, token: token)
            busy = nil
            if let error {
                model.feedback = .failure(error)
            } else {
                // The banner sits above the whole stack, so it is still there on the People page after the pop.
                model.feedback = .success("\(person.label) deleted",
                                          detail: model.deletedSupported ? RecentlyDeleted.deleteMessage : nil)
                dismiss()
            }
        }
    }

    private func logOutAll() {
        guard busy == nil, let person, let token else { return }
        busy = .logOutAll
        model.feedback = nil
        Task {
            let error = await model.logOutAll(code: person.code, token: token)
            busy = nil
            model.feedback = error.map(ActionFeedback.failure) ?? .success("Devices logged out")
        }
    }

    private func logOut(_ row: PersonDevice) {
        guard busy == nil, let token else { return }
        busy = .device(row.id)
        model.feedback = nil
        Task {
            let error = await model.revokeDevice(row.device, token: token)
            busy = nil
            model.feedback = error.map(ActionFeedback.failure) ?? .success("\(row.device.displayName) logged out")
        }
    }

    private func rename(_ row: PersonDevice) {
        guard busy == nil, let token else { return }
        busy = .device(row.id)
        model.feedback = nil
        Task {
            await EditCommit.endEditing()
            let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != row.device.displayName else { busy = nil; return }
            let error = await model.renameDevice(row.device, displayName: name, token: token)
            busy = nil
            model.feedback = error.map(ActionFeedback.failure) ?? .success("Renamed")
        }
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
    /// A log out or rename of this device is running.
    var busy = false

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
                    if busy {
                        ProgressView().tint(Theme.Color.stone)
                    } else {
                        (Text(HomeFormat.gigabytes(row.usedGB)).font(Theme.Font.serif(19))
                            + Text(" GB").font(Theme.Font.text(11, .medium)).foregroundStyle(Theme.Color.stone))
                            .foregroundStyle(Theme.Color.ink)
                            .rollingNumber(row.usedGB)
                    }
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

    var body: some View {
        VStack(spacing: 0) {
            BarRow {
                BackButton(title: "People") { dismiss() }
            } trailing: {
                EmptyView()
            }
            .padding(.horizontal, Theme.gutter)
            list
        }
        .rfPage()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DotTitle(text: "Recently Deleted", size: 46, dot: .filled, lineLimit: 2)
                    .padding(.top, 14)
                    .entrance(0)
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.deletedError {
                        Text(error)
                            .font(Theme.Font.text(13, .medium))
                            .foregroundStyle(Theme.Color.red)
                            .padding(.top, 12)
                    }
                    Rule().padding(.top, 20)
                    if model.deleted.isEmpty {
                        Text("Nothing here")
                            .font(Theme.Font.text(14))
                            .foregroundStyle(Theme.Color.stone)
                            .padding(.vertical, 16)
                            .transition(.opacity)
                    }
                    rows
                }
                .animation(Motion.fade, value: model.deleted.map(\.id))
                .entrance(1)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .underPinnedBar()
    }

    /// A restored person's row leaves with a fade; the rest close up.
    private var rows: some View {
        let now = Date()
        return ForEach(model.deleted) { item in
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
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rule() }
            .transition(.opacity)
        }
    }

    private func restore(_ item: DeletedInvite) {
        guard !restoring.contains(item.id), let token = appState.currentProfile?.token else { return }
        restoring.insert(item.id)
        model.feedback = nil
        Task {
            let error = await model.restore(item, token: token)
            restoring.remove(item.id)
            model.feedback = error.map(ActionFeedback.failure)
                ?? .success("\(item.label) restored", detail: RecentlyDeleted.restoredNote)
        }
    }
}
