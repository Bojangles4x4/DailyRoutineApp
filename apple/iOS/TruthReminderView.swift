import SwiftUI
import PhotosUI

struct TruthReminderView: View {
    private typealias Palette = RoutineHomeWidgetPalette
    @ObservedObject var store: TruthReminderStore
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var editor: TruthReminder?
    @State private var deleting: TruthReminder?
    @State private var draft = TruthReminderSettings()
    @State private var chosen = Set<UUID>()

    private func timeBinding(_ path: WritableKeyPath<TruthReminderSettings, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: draft[keyPath: path] / 60, minute: draft[keyPath: path] % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft[keyPath: path] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable truth reminders", isOn: $draft.enabled)
                    DatePicker("Start", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    Picker("Every", selection: $draft.interval) {
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    Picker("Minimum reflection", selection: $draft.reflectionSeconds) {
                        Text("5 seconds").tag(5)
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                    }
                    Toggle("Shuffle the whole library", isOn: $draft.shuffle)
                    Toggle("Pause nonessential apps until reviewed", isOn: $draft.pauseAppsUntilReviewed)
                    if store.settings.enabled {
                        LabeledContent("Active schedule", value: store.scheduleSummary)
                        LabeledContent(
                            store.settings.pauseAppsUntilReviewed ? "Next app pause" : "Next reminder",
                            value: store.nextScheduledReminderAt?.formatted(date: .abbreviated, time: .shortened) ?? "Needs attention"
                        )
                    }
                } header: { Text("Daily schedule") } footer: {
                    Text("The end time is included. When app pausing is on, the next reminder uses a separate Screen Time shield. Your always-available Earned Access apps stay open, and the shield remains until you review the reminder.")
                }
                Section {
                    Button("Save reminder schedule") {
                        store.settings.enabled = draft.enabled
                        store.settings.startMinute = draft.startMinute
                        store.settings.endMinute = draft.endMinute
                        store.settings.interval = draft.interval
                        store.settings.reflectionSeconds = draft.reflectionSeconds
                        store.settings.shuffle = draft.shuffle
                        store.settings.pauseAppsUntilReviewed = draft.pauseAppsUntilReviewed
                        store.settings.entries = store.settings.entries.map { entry in
                            var next = entry; next.selected = chosen.contains(entry.id); return next
                        }
                        Task { await store.apply(); draft.enabled = store.settings.enabled }
                    }
                        .disabled(store.busy)
                    Text(store.status).font(.footnote).accessibilityIdentifier("truthReminderStatus")
                    if let acknowledgedAt = store.settings.lastAcknowledgedAt {
                        LabeledContent("Last acknowledged", value: acknowledgedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let safetyAt = store.lastSafetyUnlockAt {
                        LabeledContent("Safety unlocks today", value: "\(store.safetyUnlockCountToday) · last at \(safetyAt.formatted(date: .omitted, time: .shortened))")
                    }
                    if store.settings.pauseAppsUntilReviewed {
                        LabeledContent("Waiting to review", value: String(store.waitingReminderCount))
                        if let unlockUntil = store.safetyUnlockEndsAt {
                            LabeledContent("Temporary access", value: "Until \(unlockUntil.formatted(date: .omitted, time: .shortened))")
                        }
                        if store.waitingReminderCount > 0 {
                            Button(store.safetyUnlockEndsAt == nil ? "Review waiting reminders" : "End safety unlock and review") {
                                store.reviewWaitingRemindersNow()
                            }
                        }
                    }
                } footer: {
                    Text("Reminder text and pictures may appear on your lock screen. Tap the notification or “Review now” to open the full reminder, then acknowledge it inside the app. Your library stays on this iPhone and is separate from routine backups and Private sync.")
                }
                Section {
                    ForEach(store.settings.entries) { entry in
                        HStack(alignment: .top) {
                            if !draft.shuffle {
                                Toggle("Include reminder", isOn: Binding(get: { chosen.contains(entry.id) }, set: { value in
                                    if value { chosen.insert(entry.id) } else { chosen.remove(entry.id) }
                                })).labelsHidden().toggleStyle(.button)
                            }
                            Button { editor = entry } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let name = entry.imageName, let image = UIImage(contentsOfFile: store.imageURL(name).path) {
                                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                                    }
                                    Text(entry.text.isEmpty ? "Picture reminder" : entry.text).lineLimit(4).foregroundStyle(.primary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.borderless)
                            Button(role: .destructive) { deleting = entry } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete reminder")
                        }
                    }
                    Button { editor = TruthReminder(text: "") } label: { Label("Add text or picture", systemImage: "plus") }
                        .disabled(store.settings.entries.count >= 50)
                } header: { Text("Your truth library") } footer: {
                    Text("Tap an entry to edit it. When shuffle is off, select the entries you want and save the schedule.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.accent)
            .disabled(store.busy)
            .navigationTitle("Truth reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(); dismiss() } } }
            .sheet(item: $editor) { TruthReminderEditor(store: store, entry: $0) }
            .onAppear {
                draft = store.settings
                chosen = Set(store.settings.entries.filter(\.selected).map(\.id))
                Task { await store.refreshForNewDay() }
            }
            .onChange(of: store.settings.entries.map(\.id)) { old, new in
                chosen.formUnion(Set(new).subtracting(old))
                chosen.formIntersection(new)
            }
            .alert("Delete this reminder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let entry = deleting { Task { await store.remove(entry) } }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("It will be removed from your library and future reminders.") }
        }
    }
}

struct TruthReminderReviewView: View {
    private typealias Palette = RoutineHomeWidgetPalette
    @ObservedObject var store: TruthReminderStore
    let presentation: TruthReminderPresentation
    @Environment(\.scenePhase) private var scenePhase
    @State private var secondsRemaining: Int

    private var entry: TruthReminder { presentation.entry }
    private var blocking: Bool { presentation.blocking }
    private var timerTaskID: String { "\(presentation.id)|\(scenePhase == .active ? "active" : "paused")" }

    init(store: TruthReminderStore, presentation: TruthReminderPresentation) {
        self.store = store
        self.presentation = presentation
        _secondsRemaining = State(initialValue: max(0, store.settings.reflectionSeconds))
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        HStack(spacing: 9) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                            Text("Pause for a few seconds to reset your mind on what is true.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if blocking && presentation.queueTotal > 1 {
                            Text("Reminder \(presentation.queuePosition) of \(presentation.queueTotal) waiting")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.soft, in: Capsule())
                        }
                    }

                    VStack(spacing: 18) {
                        if let name = entry.imageName,
                           let image = UIImage(contentsOfFile: store.imageURL(name).path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel("Truth reminder picture")
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text)
                                .font(.system(.title3, design: .serif, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        store.acknowledge(presentation)
                    } label: {
                        Label(secondsRemaining > 0 ? "Continue in \(secondsRemaining)s" : "I’ve read this", systemImage: secondsRemaining > 0 ? "timer" : "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(secondsRemaining > 0 ? Palette.muted : Palette.onAccent)
                            .background(secondsRemaining > 0 ? Palette.soft : Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(secondsRemaining > 0)
                    .accessibilityLabel(secondsRemaining > 0 ? "Reflection timer" : "I've read this")
                    .accessibilityValue(secondsRemaining > 0 ? "\(secondsRemaining) seconds remaining" : "Ready")
                    .accessibilityIdentifier("truthReminderAcknowledgeButton")

                    if blocking {
                        Button("Safety unlock for 15 minutes") {
                            store.safetyUnlockForFifteenMinutes()
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.accent)
                        .accessibilityIdentifier("truthReminderUnlockButton")
                    } else {
                        Button("Close") {
                            store.dismissPresentation()
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.accent)
                    }

                    Text(blocking
                         ? "Review every waiting reminder to resume your apps. Safety unlock pauses this gate for 15 minutes without marking anything reviewed."
                         : "This reminder did not pause your other apps.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .interactiveDismissDisabled(blocking)
        .onChange(of: presentation.id) {
            secondsRemaining = max(0, store.settings.reflectionSeconds)
        }
        .task(id: timerTaskID) {
            guard scenePhase == .active else { return }
            while secondsRemaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled, scenePhase == .active else { return }
                secondsRemaining = TruthReminderCountdown.next(secondsRemaining, sceneIsActive: true)
            }
        }
    }
}

enum TruthReminderCountdown {
    static func next(_ secondsRemaining: Int, sceneIsActive: Bool) -> Int {
        guard sceneIsActive else { return secondsRemaining }
        return max(0, secondsRemaining - 1)
    }
}

private struct TruthReminderEditor: View {
    private typealias Palette = RoutineHomeWidgetPalette
    @ObservedObject var store: TruthReminderStore
    let entry: TruthReminder
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var keepImage = true
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Words to remember") { TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("Reminder text") }
                Section("Optional picture") {
                    if let data = photoData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    } else if keepImage, let name = entry.imageName, let image = UIImage(contentsOfFile: store.imageURL(name).path) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    }
                    PhotosPicker("Choose a picture", selection: $photo, matching: .images)
                    if photoData != nil || (keepImage && entry.imageName != nil) {
                        Button("Remove picture", role: .destructive) { photoData = nil; keepImage = false; photo = nil }
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.accent)
            .navigationTitle("Edit truth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.saveEntry(id: entry.id, text: text, imageData: photoData, keepImage: keepImage) { dismiss() }
                            else { error = store.status }
                        }
                    }.disabled(loading || store.busy || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photoData == nil && (!keepImage || entry.imageName == nil)))
                }
            }
            .onAppear { text = entry.text }
            .onChange(of: photo) { _, selection in
                Task {
                    loading = true
                    defer { loading = false }
                    do {
                        guard let data = try await selection?.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                            if selection != nil { error = "That picture could not be loaded." }; return
                        }
                        photoData = data; keepImage = true; error = ""
                    } catch { self.error = "Could not load that picture: \(error.localizedDescription)" }
                }
            }
        }
    }
}
