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
                } header: { Text("Daily schedule") } footer: {
                    Text("The end time is included. The schedule repeats daily, even while the app is closed. A shuffled mix refreshes when you open the app on a new day; otherwise the previous mix repeats.")
                }
                Section {
                    Button("Save reminder schedule") {
                        store.settings.enabled = draft.enabled
                        store.settings.startMinute = draft.startMinute
                        store.settings.endMinute = draft.endMinute
                        store.settings.interval = draft.interval
                        store.settings.shuffle = draft.shuffle
                        store.settings.entries = store.settings.entries.map { entry in
                            var next = entry; next.selected = chosen.contains(entry.id); return next
                        }
                        Task { await store.apply(); draft.enabled = store.settings.enabled }
                    }
                        .disabled(store.busy)
                    Text(store.status).font(.footnote).accessibilityIdentifier("truthReminderStatus")
                } footer: {
                    Text("Reminder text and pictures may appear on your lock screen. Your library stays on this iPhone and is separate from routine backups and Private sync.")
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
