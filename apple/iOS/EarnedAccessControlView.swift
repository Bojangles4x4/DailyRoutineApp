import FamilyControls
import SwiftUI

struct EarnedAccessControlView: View {
    @ObservedObject var store: EarnedAccessControlStore
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
                    if store.isShielding {
                        Button("Remove test lock") { store.clearShield() }
                    } else {
                        Button("Apply test lock") {
                            store.saveSelection()
                            store.applyShield()
                        }
                        .disabled(!store.isAuthorized || !store.hasSelection)
                    }
                } header: {
                    Text("Local lock test")
                } footer: {
                    Text("Apply the lock, leave Daily Routine, and open a selected app. Apple should replace it with a Screen Time shield. Return here to remove the lock. Routine-based and timed unlocking comes after this device test succeeds.")
                }
            }
            .navigationTitle("Earned Access test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
