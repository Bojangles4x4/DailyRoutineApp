import FamilyControls
import SwiftUI
import UIKit

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
                    HStack(spacing: 12) {
                        Image(systemName: protectionSymbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(protectionColor)
                            .frame(width: 38, height: 38)
                            .background(protectionColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(protectionTitle)
                                .font(.headline)
                            Text(protectionDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    LabeledContent("Morning gate", value: store.morningGateEnabled ? "On" : "Off")
                    LabeledContent("Earned-app protection", value: store.protectionEnabled ? "On" : "Off")
                    if store.protectionEnabled {
                        LabeledContent("Daily reset", value: store.dailyResetScheduled ? "Scheduled" : "Needs attention")
                    }
                    if store.morningGateEnabled {
                        LabeledContent("Morning schedule", value: store.morningGateScheduled ? "Scheduled" : "Needs attention")
                    }
                    LabeledContent("Usage notifications", value: store.notificationsAllowed ? "Allowed" : "Not allowed")
                    if !store.notificationsAllowed {
                        if store.notificationsDenied {
                            Button("Open iPhone notification settings") {
                                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                UIApplication.shared.open(url)
                            }
                        } else {
                            Button("Allow usage notifications") {
                                Task { await store.requestUsageNotifications() }
                            }
                        }
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("Unused earned minutes expire at midnight. Each new day begins locked until Truth Before Tasks and any configured convictions are complete.")
                }

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
                    Text("Apps that use earned minutes")
                } footer: {
                    Text("Choose the social, retail, or other nonessential apps that should use your earned time bank. All selected apps share one bank, and their combined foreground use spends the allowance.")
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
                    Text("Earned-app protection")
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
                    Text("Apps available before the opening")
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

    private var protectionTitle: String {
        if !store.isAuthorized { return "Screen Time setup needed" }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday {
            return "Locked until Truth Before Tasks"
        }
        if !store.morningGateEnabled { return "Morning gate is off" }
        if !store.protectionEnabled { return "Earned-app protection is off" }
        if store.allowanceActive {
            if let remaining = store.allowanceRemainingMinutes { return "About \(remaining) earned minutes available" }
            return "Earned apps are available"
        }
        return store.isShielding ? "Earned apps are locked" : "Protection is ready"
    }

    private var protectionDetail: String {
        if !store.isAuthorized { return "Allow access, then choose the apps to manage." }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday {
            return "Yesterday’s unused minutes cannot open apps today."
        }
        if !store.morningGateEnabled { return "Turn it on to protect the start of each day." }
        if !store.protectionEnabled { return "Turn it on before relying on the earned time bank." }
        if store.allowanceActive { return "Only foreground use in selected apps reduces the shared balance." }
        return "Complete a selected routine or keep walking to earn time."
    }

    private var protectionSymbol: String {
        if store.morningGateEnabled && !store.morningFoundationCompleteToday { return "lock.shield.fill" }
        if store.allowanceActive { return "checkmark.circle.fill" }
        return store.isAuthorized && store.protectionEnabled ? "shield.fill" : "exclamationmark.triangle.fill"
    }

    private var protectionColor: Color {
        if store.allowanceActive { return .green }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday { return .orange }
        return store.isAuthorized && store.protectionEnabled ? .teal : .orange
    }
}
