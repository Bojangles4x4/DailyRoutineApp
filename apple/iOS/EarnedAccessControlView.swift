import FamilyControls
import SwiftUI

struct EarnedAccessControlView: View {
    @ObservedObject var store: EarnedAccessControlStore
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false
    @State private var showingEssentialPicker = false

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
                    Text("Earned apps")
                } footer: {
                    Text("Choose the social, retail, or other nonessential apps that should use your earned time bank.")
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
                    Text("When protection is on, selected apps remain shielded until Daily Routine grants an allowance. Only actual foreground use counts against it.")
                }

                Section {
                    LabeledContent("Always-available apps", value: String(store.essentialApplicationCount))
                    LabeledContent("Always-available websites", value: String(store.essentialWebsiteCount))
                    Button("Choose essential apps") { showingEssentialPicker = true }
                        .disabled(!store.isAuthorized)
                    Button("Save essential selection") { store.saveEssentialSelection() }
                        .disabled(!store.isAuthorized || !store.hasEssentialSelection)
                    if store.morningGateEnabled {
                        Button("Turn off morning gate") { store.disableMorningGate() }
                    } else {
                        Button("Turn on morning Truth gate") {
                            store.saveEssentialSelection()
                            store.enableMorningGate()
                        }
                        .disabled(!store.isAuthorized || !store.hasEssentialSelection)
                    }
                } header: {
                    Text("Before Truth Before Tasks")
                } footer: {
                    Text("The morning gate shields nearly every app until today’s opening is complete. Daily Routine stays available automatically. Choose individual essentials such as Messages and navigation before turning it on.")
                }
            }
            .navigationTitle("Earned Access")
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
            .familyActivityPicker(isPresented: $showingEssentialPicker, selection: $store.essentialSelection)
            .onChange(of: showingPicker) { _, isShowing in
                if !isShowing { store.saveSelection() }
            }
            .onChange(of: showingEssentialPicker) { _, isShowing in
                if !isShowing { store.saveEssentialSelection() }
            }
            .onAppear { store.refresh() }
            .interactiveDismissDisabled()
        }
    }

    private var authorizationLabel: String {
        if store.isAuthorized { return "Allowed" }
        if store.authorizationStatus == .denied { return "Not allowed" }
        if store.authorizationStatus == .notDetermined { return "Not requested" }
        return "Unavailable"
    }
}
