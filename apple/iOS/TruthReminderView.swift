import SwiftUI
import PhotosUI

struct TruthReminderView: View {
    @ObservedObject var store: TruthReminderStore
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
                    Toggle("Shuffle the whole library", isOn: $draft.shuffle)
                    Toggle("Pause nonessential apps until reviewed", isOn: $draft.pauseAppsUntilReviewed)
                    if store.settings.enabled {
                        LabeledContent("Active schedule", value: store.scheduleSummary)
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
            .disabled(store.busy)
            .navigationTitle("Truth reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editor) { TruthReminderEditor(store: store, entry: $0) }
            .onAppear { draft = store.settings; chosen = Set(store.settings.entries.filter(\.selected).map(\.id)) }
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
    @ObservedObject var store: TruthReminderStore
    let entry: TruthReminder
    let blocking: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.97, blue: 0.95), Color(red: 0.98, green: 0.95, blue: 0.89)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 7) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.30))
                        Text("A moment of truth")
                            .font(.system(.title2, design: .serif, weight: .bold))
                        Text("Pause here before returning to other apps.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 18) {
                        if let name = entry.imageName,
                           let image = UIImage(contentsOfFile: store.imageURL(name).path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .accessibilityLabel("Truth reminder picture")
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text)
                                .font(.system(.title3, design: .serif, weight: .medium))
                                .foregroundStyle(Color(red: 0.10, green: 0.25, blue: 0.22))
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(22)
                    .background(.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Button {
                        store.acknowledge(entry)
                    } label: {
                        Label("I’ve read this", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.12, green: 0.35, blue: 0.30))
                    .accessibilityIdentifier("truthReminderAcknowledgeButton")

                    if blocking {
                        Button("Unlock for now") {
                            store.unlockCurrentReminder()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("truthReminderUnlockButton")
                    } else {
                        Button("Close") {
                            store.dismissPresentation()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(blocking
                         ? "Your other apps will resume after you acknowledge this reminder. If the reminder cannot be reviewed, Unlock for now safely clears this pause."
                         : "This reminder did not pause your other apps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 34)
            }
        }
        .interactiveDismissDisabled(blocking)
    }
}

private struct TruthReminderEditor: View {
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
