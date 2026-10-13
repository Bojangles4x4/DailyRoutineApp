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
                    if store.truthReminderGateActive {
                        LabeledContent("Controlling access", value: "Truth Reminder")
                    } else if let unlockUntil = store.truthReminderSafetyUnlockUntil {
                        LabeledContent("Truth safety access", value: "Until \(unlockUntil.formatted(date: .omitted, time: .shortened))")
                    }
                    LabeledContent("Usage notifications", value: store.notificationsAllowed ? "Allowed" : "Not allowed")
                    if store.allowanceActive {
                        LabeledContent(
                            accessBlockedByHigherGate ? "Earned allowance" : "Currently open",
                            value: store.allowanceRemainingMinutes.map {
                                accessBlockedByHigherGate ? "Bank preserved · about \($0) min" : "About \($0) min"
                            } ?? "Refreshing"
                        )
                        LabeledContent("Allowance monitor", value: store.allowanceMonitorScheduled ? "Active" : "Repairing")
                    }
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
                    if store.essentialSelectionNeedsRepair {
                        Label("Choose at least one essential app before turning on an all-app gate.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
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
        EarnedAccessProtectionSummary.title(
            isAuthorized: store.isAuthorized,
            essentialSelectionNeedsRepair: store.essentialSelectionNeedsRepair,
            morningGateEnabled: store.morningGateEnabled,
            morningFoundationCompleteToday: store.morningFoundationCompleteToday,
            truthReminderGateActive: store.truthReminderGateActive,
            truthReminderSafetyUnlockActive: store.truthReminderSafetyUnlockUntil != nil,
            protectionEnabled: store.protectionEnabled,
            allowanceActive: store.allowanceActive,
            allowanceRemainingMinutes: store.allowanceRemainingMinutes,
            isShielding: store.isShielding
        )
    }

    private var protectionDetail: String {
        if !store.isAuthorized { return "Allow access, then choose the apps to manage." }
        if store.essentialSelectionNeedsRepair {
            return "All-app gates are released for safety until you choose essential apps again."
        }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday {
            return "Yesterday’s unused minutes cannot open apps today."
        }
        if store.truthReminderGateActive {
            return "Review every waiting reminder before nonessential apps reopen."
        }
        if let unlockUntil = store.truthReminderSafetyUnlockUntil {
            return "Temporary access ends at \(unlockUntil.formatted(date: .omitted, time: .shortened)), then waiting reminders take control again."
        }
        if !store.protectionEnabled { return "Turn it on before relying on the earned time bank." }
        if store.allowanceActive { return "Only foreground use in selected apps reduces what is currently open. All selected apps share the same daily bank." }
        return "Complete a selected routine or keep walking to earn time."
    }

    private var protectionSymbol: String {
        if store.essentialSelectionNeedsRepair { return "exclamationmark.triangle.fill" }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday { return "lock.shield.fill" }
        if store.truthReminderGateActive { return "bell.badge.fill" }
        if store.truthReminderSafetyUnlockUntil != nil { return "timer" }
        if store.allowanceActive { return "checkmark.circle.fill" }
        return store.isAuthorized && store.protectionEnabled ? "shield.fill" : "exclamationmark.triangle.fill"
    }

    private var protectionColor: Color {
        if store.essentialSelectionNeedsRepair { return .orange }
        if store.morningGateEnabled && !store.morningFoundationCompleteToday { return .orange }
        if store.truthReminderGateActive { return .orange }
        if store.truthReminderSafetyUnlockUntil != nil { return .orange }
        if store.allowanceActive { return .green }
        return store.isAuthorized && store.protectionEnabled ? .teal : .orange
    }

    private var accessBlockedByHigherGate: Bool {
        !store.essentialSelectionNeedsRepair
            && ((store.morningGateEnabled && !store.morningFoundationCompleteToday) || store.truthReminderGateActive)
    }
}

enum EarnedAccessProtectionSummary {
    static func title(
        isAuthorized: Bool,
        essentialSelectionNeedsRepair: Bool,
        morningGateEnabled: Bool,
        morningFoundationCompleteToday: Bool,
        truthReminderGateActive: Bool,
        truthReminderSafetyUnlockActive: Bool,
        protectionEnabled: Bool,
        allowanceActive: Bool,
        allowanceRemainingMinutes: Int?,
        isShielding: Bool
    ) -> String {
        if !isAuthorized { return "Screen Time setup needed" }
        if essentialSelectionNeedsRepair { return "Essential app setup needs repair" }
        if morningGateEnabled && !morningFoundationCompleteToday { return "Locked until Truth Before Tasks" }
        if truthReminderGateActive { return "Paused for a Truth Reminder" }
        if truthReminderSafetyUnlockActive { return "Truth safety access is open" }
        if !protectionEnabled { return "Earned-app protection is off" }
        if allowanceActive {
            if let allowanceRemainingMinutes { return "Currently open: about \(allowanceRemainingMinutes) min" }
            return "Currently open: refreshing"
        }
        return isShielding ? "Earned apps are locked" : "Protection is ready"
    }
}
