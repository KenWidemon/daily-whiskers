import SwiftUI

struct ReminderSettingsView: View {
    @ObservedObject var model: ReminderModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var editingTime = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily Reminder", isOn: Binding(get: { model.status.enabled }, set: { value in
                        Task { await model.send(.enable(value)) }
                    }))
                    .accessibilityIdentifier("reminder-enabled")
                    .accessibilityHint("An optional notification at your chosen time. Turning it off clears pending and delivered reminders.")
                    .disabled(model.busy || !model.loaded)
                    Button { editingTime = true } label: {
                        Group {
                            if textSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Reminder Time")
                                    Text(Self.displayTime(model.status.time)).foregroundStyle(Color(uiColor: .secondaryLabel))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                HStack {
                                    Text("Reminder Time")
                                    Spacer()
                                    Text(Self.displayTime(model.status.time)).foregroundStyle(Color(uiColor: .secondaryLabel))
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                                }
                            }
                        }.foregroundStyle(Color(uiColor: .label)).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Reminder Time")
                    .accessibilityValue(Self.displayTime(model.status.time))
                    .accessibilityIdentifier("reminder-time")
                    .accessibilityHint("Edit the time without turning reminders on.")
                    .disabled(model.busy || !model.loaded)
                } footer: {
                    Text("An alert only, without sound or a badge. Reminders stay quiet while you're using the app.")
                }
                Section("Notification Permission") {
                    Text(permissionText).accessibilityIdentifier("reminder-permission")
                    if model.status.authorization == .denied {
                        Button("Open iOS Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                            .frame(minHeight: 44).accessibilityIdentifier("reminder-open-system-settings")
                    } else if model.status.authorization == .notDetermined && model.status.enabled {
                        Button("Allow Notifications") { Task { await model.send(.enable(true)) } }
                            .frame(minHeight: 44).disabled(model.busy)
                    }
                    Text("iOS controls delivery timing. Focus, Scheduled Summary and your notification settings may delay or hide an alert.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Reminder Coverage") {
                    Text("Reminders are scheduled for up to 14 days. Open Daily Whiskers to keep them going. They can stop if you don't open the app for two weeks.")
                    Text("When you travel, queued reminders keep the previous time zone until you reopen the app. Crossing the date line without reopening can put two reminders on the same local date.")
                    Text("Missed reminders aren't caught up. Changes may skip a reminder when its previous delivery is uncertain, to avoid duplicates.")
                    if model.status.enabled && model.status.authorization.canSchedule {
                        Text(coverageText).accessibilityIdentifier("reminder-coverage-status")
                    }
                }
                if let message = model.status.message {
                    Section { Text(message).accessibilityIdentifier("reminder-error") }
                }
                if model.busy { ProgressView("Updating reminders…") }
#if DEBUG && CI_SMOKE_TESTING
                if ReminderSmoke.controlsEnabled { Section { ReminderSmokeControls(model: model, context: "sheet") } }
#endif
            }
            .navigationTitle("Daily Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("reminder-done")
                }
            }
            .sheet(isPresented: $editingTime) {
                ReminderTimeEditor(time: model.status.time) { value in
                    await model.send(.time(value))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var permissionText: String {
        switch model.status.authorization {
        case .notDetermined: return "Permission will be requested only when you turn reminders on."
        case .denied: return model.status.enabled
            ? "Blocked in iOS Settings. Your time and enabled preference are kept. After allowing notifications, reopen the app to resume."
            : "Notifications aren't allowed. Reminders stay off until you enable them."
        case .authorized: return "Notifications allowed."
        case .quiet: return "Quiet notifications allowed. Check iOS Settings for alert presentation."
        }
    }
    private var coverageText: String {
        guard let end = model.status.coverageEnd else { return "No upcoming reminders are confirmed. Open the app again to check coverage." }
        return "\(model.status.queued) upcoming reminders, through \(end.formatted(date: .abbreviated, time: .shortened))."
    }
    static func displayTime(_ time: ReminderTime) -> String {
        let format = DateFormatter(); format.dateStyle = .none; format.timeStyle = .short
        format.timeZone = TimeZone(secondsFromGMT: 0)!
        return format.string(from: editorDate(time))
    }
    static func editorDate(_ time: ReminderTime) -> Date {
        ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!).date(from:
            DateComponents(year: 2001, month: 1, day: 15, hour: time.hour, minute: time.minute))!
    }
}

private struct ReminderTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var saving = false
    let save: (ReminderTime) async -> Void
    init(time: ReminderTime, save: @escaping (ReminderTime) async -> Void) {
        _date = State(initialValue: ReminderSettingsView.editorDate(time)); self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Reminder Time", selection: $date, displayedComponents: .hourAndMinute)
                    .environment(\.calendar, ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!))
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .accessibilityIdentifier("reminder-time-picker")
                Text("Choose a local time. Saving it doesn't turn reminders on.")
#if DEBUG && CI_SMOKE_TESTING
                if ReminderSmoke.controlsEnabled {
                    Button("Test reminder tap") { ReminderModel.shared.receiveTap(identifier: ReminderRequest.prefix + "old", destination: "today") }
                        .accessibilityIdentifier("editor-reminder-test-tap")
                }
#endif
            }
            .navigationTitle("Time")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("reminder-time-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Time") {
                        saving = true
                        let parts = ReminderCalendar.calendar(TimeZone(secondsFromGMT: 0)!).dateComponents([.hour, .minute], from: date)
                        Task { await save(ReminderTime(hour: parts.hour!, minute: parts.minute!)); dismiss() }
                    }.disabled(saving).accessibilityIdentifier("reminder-time-save")
                }
            }
        }
    }
}
