import FamilyControls
import SwiftUI

struct EarnedAccessControlView: View {
    @ObservedObject var store: EarnedAccessControlStore
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Screen Time access", value: authorizationLabel)
                    if !store.isAuthorized {
                        Button("Allow Screen Time access") {
                            Task { await store.requestAuthorization() }
                        }
                    }
                    Text(store.status)
                        .font(.footnote)
                        .accessibilityIdentifier("earnedAccessNativeStatus")
                } header: {
                    Text("Permission")
                } footer: {
                    Text("Your app and website choices are represented by private Apple tokens. Daily Routine does not receive their names or your browsing history.")
                }

                Section {
                    LabeledContent("Apps", value: String(store.selectedApplicationCount))
                    LabeledContent("Categories", value: String(store.selectedCategoryCount))
                    LabeledContent("Websites", value: String(store.selectedWebsiteCount))
                    Button("Choose apps and websites") { showingPicker = true }
                        .disabled(!store.isAuthorized)
                    Button("Save selection") { store.saveSelection() }
                        .disabled(!store.isAuthorized || !store.hasSelection)
                } header: {
                    Text("Private selection")
                } footer: {
                    Text("For the first test, choose one nonessential app. You can change the selection at any time.")
                }

                Section {
                    if store.protectionEnabled {
                        Button("Turn off Earned Access protection") { store.disableProtection() }
                    } else {
                        Button("Turn on Earned Access protection") {
                            store.saveSelection()
                            store.enableProtection()
                        }
                        .disabled(!store.isAuthorized || !store.hasSelection)
                    }
                } header: {
                    Text("Protection")
                } footer: {
                    Text("When protection is on, selected apps remain shielded until Daily Routine grants an earned allowance. Turn protection off here if you need to remove every Earned Access restriction immediately.")
                }
            }
            .navigationTitle("Earned Access test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.refresh()
                        onDone()
                        dismiss()
                    }
                }
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $store.selection)
            .onChange(of: showingPicker) { _, isShowing in
                if !isShowing { store.saveSelection() }
            }
            .onAppear { store.refresh() }
        }
    }

    private var authorizationLabel: String {
        if store.isAuthorized { return "Allowed" }
        if store.authorizationStatus == .denied { return "Not allowed" }
        if store.authorizationStatus == .notDetermined { return "Not requested" }
        return "Unavailable"
    }
}
