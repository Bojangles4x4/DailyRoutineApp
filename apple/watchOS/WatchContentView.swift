import SwiftUI
import WatchKit

private enum WatchLedgerPalette {
    static let background = Color(red: 0.039, green: 0.059, blue: 0.075)
    static let surface = Color(red: 0.071, green: 0.110, blue: 0.137)
    static let soft = Color(red: 0.102, green: 0.169, blue: 0.208)
    static let ink = Color(red: 0.957, green: 0.973, blue: 0.980)
    static let muted = Color(red: 0.68, green: 0.76, blue: 0.81)
    static let accent = Color(red: 0.49, green: 0.75, blue: 0.93)
    static let button = Color(red: 0.173, green: 0.424, blue: 0.588)
}

private struct WatchDeferredSuggestions: Codable {
    let localDateKey: String
    let timeZoneIdentifier: String
    let itemIDs: [String]
}

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @AppStorage("watch-deferred-suggestions-v1") private var deferredSuggestionPayload = ""
    @State private var pendingMedicationItem: WatchRoutineItem?
    @State private var medicationToReview: WatchRoutineItem?
    @State private var deferredSuggestionIDs: [String] = []
    @State private var pendingDeliveryItemID: String?
    @State private var deliveryFeedback: String?
    private typealias Palette = WatchLedgerPalette

    private var progress: Double {
        guard let context = session.context, context.total > 0 else { return 0 }
        return min(max(Double(context.completed) / Double(context.total), 0), 1)
    }

    private var truthBeforeTasksComplete: Bool {
        contextIsCurrentDay
            && session.context?.truthBeforeTasksComplete == true
    }

    private var contextIsCurrentDay: Bool {
        session.context?.dateKey == localDateKey
            && session.context?.timeZoneIdentifier == TimeZone.current.identifier
    }

    private var localDateKey: String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var routineItems: [WatchRoutineItem] { session.context?.items ?? [] }
    private var incompleteItems: [WatchRoutineItem] { routineItems.filter { !$0.completed } }
    private var suggestedItem: WatchRoutineItem? {
        orderedSuggestionItems.first
    }
    private var nextSuggestedItem: WatchRoutineItem? {
        orderedSuggestionItems.dropFirst().first
    }
    private var orderedSuggestionItems: [WatchRoutineItem] {
        let active = incompleteItems.filter { !deferredSuggestionIDs.contains($0.id) }
        let deferred = deferredSuggestionIDs.compactMap { id in
            incompleteItems.first { $0.id == id }
        }
        return active + deferred
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 5) {
                if !contextIsCurrentDay {
                    refreshHeader
                    refreshCard
                    Spacer(minLength: 0)
                } else if truthBeforeTasksComplete {
                    summaryHeader
                    stepsStrip
                    suggestedFocus
                } else {
                    lockedHeader
                    truthLockCard
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(Palette.ink)
        .sheet(item: $medicationToReview) { item in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name).font(.headline)
                    ForEach(Array(item.medicationList ?? []), id: \.self) { medication in
                        Text(medication).font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Reminder only. Complete the routine once after taking your medications.")
                        .font(.caption2).foregroundStyle(Palette.muted)
                    Button("Done") { medicationToReview = nil }
                        .accessibilityIdentifier("dismissMedicationReview")
                }.padding(12)
            }
            .background(Palette.background)
            .accessibilityIdentifier("watchMedicationReview")
        }
        .alert(item: $pendingMedicationItem) { item in
            Alert(
                title: Text("Check medication time"),
                message: Text(medicationConfirmationMessage(item)),
                primaryButton: .cancel(),
                secondaryButton: .default(Text("Log now")) { sendRoutineAction(item) }
            )
        }
        .onChange(of: session.context?.dateKey) {
            restoreDeferredSuggestions()
        }
        .onChange(of: session.context?.completed) {
            pendingDeliveryItemID = nil
            deliveryFeedback = nil
        }
        .onAppear(perform: restoreDeferredSuggestions)
    }

    private var summaryHeader: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 4) {
                Text("Today").font(.system(size: 14, weight: .semibold))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("watchProgressPercent")
                Circle()
                    .fill(session.isReachable ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(session.isReachable ? "Live" : "Will sync")
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 5)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.soft)
                    Capsule().fill(Palette.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .accessibilityLabel("Routine progress")
            .accessibilityValue("\(session.context?.completed ?? 0) of \(session.context?.total ?? 0) complete")
        }
        .accessibilityIdentifier("watchSummaryHeader")
    }

    private var lockedHeader: some View {
        VStack(spacing: 3) {
            HStack {
                Text("Today").font(.system(size: 14, weight: .semibold))
                Label("Locked", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("watchLockStatus")
                Spacer()
            }
            .padding(.horizontal, 5)
            Capsule().fill(Palette.soft).frame(height: 4)
        }
        .accessibilityIdentifier("watchLockedHeader")
    }

    private var refreshHeader: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Text("Today").font(.system(size: 14, weight: .semibold))
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Spacer()
            }
            .padding(.horizontal, 5)
            Capsule().fill(Palette.soft).frame(height: 4)
        }
        .accessibilityIdentifier("watchRefreshHeader")
    }

    private var stepsStrip: some View {
        HStack {
            Text("Steps")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Palette.muted)
                .textCase(.uppercase)
            Spacer()
            if let steps = session.context?.stepCount {
                Text(steps.formatted())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } else {
                Text("Open iPhone")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityIdentifier("watchStepsSummary")
    }

    private var suggestedFocus: some View {
        VStack(spacing: 7) {
            if let item = suggestedItem {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sectionTitle(item.section))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.accent)
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.top, 4)

                    Spacer(minLength: 4)

                    if pendingDeliveryItemID == item.id, let deliveryFeedback {
                        Label(deliveryFeedback, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.green)
                            .padding(.top, 6)
                            .overlay(alignment: .top) { Divider().overlay(Palette.soft) }
                            .accessibilityIdentifier("watchDeliveryStatus")
                    } else if item.action == .takeMedication, !(item.medicationList ?? []).isEmpty {
                        Button { medicationToReview = item } label: {
                            Text("Review medications")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reviewWatchMedications")
                    } else if let nextSuggestedItem {
                        HStack(spacing: 3) {
                            Text("Up next ·")
                                .foregroundStyle(Palette.muted)
                            Text(nextSuggestedItem.name)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.top, 6)
                        .overlay(alignment: .top) { Divider().overlay(Palette.soft) }
                        .accessibilityIdentifier("watchUpNext")
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 108, maxHeight: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 7) {
                    focusActionButton(
                        title: "Later",
                        color: Palette.soft,
                        identifier: "deferSuggestedRoutineAction",
                        enabled: nextSuggestedItem != nil && pendingDeliveryItemID != item.id
                    ) { deferSuggestion(item) }
                    focusActionButton(
                        title: "Complete",
                        color: Palette.button,
                        identifier: "suggestedRoutineAction",
                        enabled: pendingDeliveryItemID != item.id
                    ) { performRoutineAction(item) }
                }
            } else {
                Label("All Watch-ready tasks complete", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func focusActionButton(
        title: String,
        color: Color,
        identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(color, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }

    private func deferSuggestion(_ item: WatchRoutineItem) {
        guard incompleteItems.contains(where: { $0.id != item.id }) else { return }
        deferredSuggestionIDs.removeAll { $0 == item.id }
        deferredSuggestionIDs.append(item.id)
        if incompleteItems.allSatisfy({ deferredSuggestionIDs.contains($0.id) }) {
            deferredSuggestionIDs = [item.id]
        }
        saveDeferredSuggestions()
        WKInterfaceDevice.current().play(.click)
    }

    private func restoreDeferredSuggestions() {
        guard
            let data = deferredSuggestionPayload.data(using: .utf8),
            let saved = try? JSONDecoder().decode(WatchDeferredSuggestions.self, from: data),
            saved.localDateKey == session.context?.dateKey,
            saved.timeZoneIdentifier == session.context?.timeZoneIdentifier
        else {
            deferredSuggestionIDs = []
            deferredSuggestionPayload = ""
            return
        }
        deferredSuggestionIDs = saved.itemIDs
    }

    private func saveDeferredSuggestions() {
        guard let context = session.context else { return }
        let saved = WatchDeferredSuggestions(
            localDateKey: context.dateKey,
            timeZoneIdentifier: context.timeZoneIdentifier ?? TimeZone.current.identifier,
            itemIDs: deferredSuggestionIDs
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        deferredSuggestionPayload = String(decoding: data, as: UTF8.self)
    }

    private func performRoutineAction(_ item: WatchRoutineItem) {
        if item.action == .takeMedication, !item.completed, medicationPeriodDoesNotMatch(item) {
            pendingMedicationItem = item
            return
        }
        sendRoutineAction(item)
    }

    private func sendRoutineAction(_ item: WatchRoutineItem) {
        guard pendingDeliveryItemID != item.id else { return }
        pendingDeliveryItemID = item.id
        session.send(WatchEvent(action: item.action, itemId: item.id))
        deliveryFeedback = session.deliveryStatus ?? "Sent to iPhone"
        WKInterfaceDevice.current().play(.click)

        let itemID = item.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard pendingDeliveryItemID == itemID else { return }
            pendingDeliveryItemID = nil
            deliveryFeedback = nil
        }
    }

    private func medicationPeriodDoesNotMatch(_ item: WatchRoutineItem) -> Bool {
        let isPM = Calendar.current.component(.hour, from: Date()) >= 12
        return (item.section == "morning" && isPM) || (item.section == "evening" && !isPM)
    }

    private func medicationConfirmationMessage(_ item: WatchRoutineItem) -> String {
        let time = Date().formatted(date: .omitted, time: .shortened)
        return "\(item.name) is in your \(sectionTitle(item.section).lowercased()) routine, but it is \(time). Log it anyway?"
    }

    private var truthLockCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(Palette.accent)
            Text("Review Truth Before Tasks on iPhone")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            Text("Your routine list and actions will unlock automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("truthBeforeTasksLock")
    }

    private var refreshCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(Palette.accent)
            Text("Open iPhone to refresh")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
            Text("Today’s routine will appear automatically. Yesterday’s data is unchanged.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watchRefreshRequired")
    }

    private func sectionTitle(_ section: String) -> String {
        switch section {
        case "morning": "Morning"
        case "evening": "Evening"
        default: "Day"
        }
    }
}
