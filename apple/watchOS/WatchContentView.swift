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

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var pendingMedicationItem: WatchRoutineItem?
    @State private var showAllTasks = false
    @State private var medicationToReview: WatchRoutineItem?
    private typealias Palette = WatchLedgerPalette

    private var progress: Double {
        guard let context = session.context, context.total > 0 else { return 0 }
        return min(max(Double(context.completed) / Double(context.total), 0), 1)
    }

    private var truthBeforeTasksComplete: Bool {
        session.context?.dateKey == localDateKey
            && session.context?.timeZoneIdentifier == TimeZone.current.identifier
            && session.context?.truthBeforeTasksComplete == true
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
    private var suggestedItem: WatchRoutineItem? { routineItems.first { !$0.completed } }

    private var healthUpdatedDate: Date? {
        guard let value = session.context?.healthUpdatedAt else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private var customAction: WatchCustomAction {
        session.context?.customAction ?? WatchCustomAction(
            title: "Water +1",
            action: .addWater,
            itemId: nil,
            value: 1
        )
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 6) {
                summaryHeader

                if truthBeforeTasksComplete {
                    if showAllTasks { routineList } else { suggestedFocus }
                    actionBar
                } else {
                    truthLockCard
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
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
    }

    private var summaryHeader: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 4) {
                Text("Today").font(.system(size: 12, weight: .medium))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
                Text("\(session.context?.completed ?? 0)/\(session.context?.total ?? 0)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Circle()
                    .fill(session.isReachable ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(session.isReachable ? "Live" : "Will sync")
                Spacer(minLength: 42)
            }
            .padding(.leading, 7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.soft)
                    Capsule().fill(Palette.accent).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.trailing, 48)
            .accessibilityLabel("Routine progress")
            .accessibilityValue("\(session.context?.completed ?? 0) of \(session.context?.total ?? 0) complete")
        }
    }

    private var suggestedFocus: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                focusSummary

                if let item = suggestedItem {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Suggested focus · \(sectionTitle(item.section))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        Text(item.name)
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if item.action == .takeMedication, !(item.medicationList ?? []).isEmpty {
                                Button { medicationToReview = item } label: {
                                    Text("Review list").font(.system(size: 10, weight: .medium))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("reviewWatchMedications")
                            }
                            Button { performRoutineAction(item) } label: {
                                Text("Mark complete")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .background(Palette.button, in: RoundedRectangle(cornerRadius: 11))
                                    .foregroundStyle(Palette.ink)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("suggestedRoutineAction")
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Label("All Watch-ready tasks complete", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let status = session.deliveryStatus {
                    Text(status).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var focusSummary: some View {
        let morning = routineItems.filter { $0.section == "morning" }
        return HStack(spacing: 6) {
            summaryTile("Morning", value: "\(morning.filter(\.completed).count) of \(morning.count)")
            summaryTile("Steps", value: session.context?.stepCount?.formatted() ?? "Open iPhone")
        }
        .accessibilityIdentifier("watchFocusSummary")
    }

    private func summaryTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var stepsSummary: some View {
        if let steps = session.context?.stepCount {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(steps.formatted()) steps").font(.system(size: 9, weight: .bold))
                if let updated = healthUpdatedDate {
                    Text(updated.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(steps) steps, last updated \(healthUpdatedDate?.formatted(date: .omitted, time: .shortened) ?? "recently")")
        }
    }

    private var routineList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                HStack {
                    Text("ALL TASKS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepsSummary
                }
                if routineItems.isEmpty {
                    Text("No Watch-ready routines today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                } else {
                    ForEach(routineItems) { item in routineButton(item) }
                }
                if let deliveryStatus = session.deliveryStatus {
                    Text(deliveryStatus).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
        .clipped()
    }

    private func routineButton(_ item: WatchRoutineItem) -> some View {
        Button { performRoutineAction(item) } label: {
            HStack(spacing: 9) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.completed ? Palette.accent : Palette.muted)
                    .font(.system(size: 17, weight: .semibold))
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(sectionTitle(item.section))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 9)
            .background(item.completed ? Palette.surface : Palette.soft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routine-\(item.id)")
        .accessibilityLabel(item.completed ? "\(item.name), completed" : item.name)
        .accessibilityHint(item.completed ? "Tap to reopen" : "Tap to complete")
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            compactAction(title: customAction.title, systemImage: customActionIcon, color: Palette.soft, identifier: "customWatchAction") {
                performCustomAction()
            }
            compactAction(
                title: showAllTasks ? "Focus" : "All tasks",
                systemImage: showAllTasks ? "scope" : "list.bullet",
                color: Palette.soft,
                identifier: "toggleWatchTaskView"
            ) { showAllTasks.toggle() }
        }
    }

    private func compactAction(
        title: String,
        systemImage: String,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var customActionIcon: String {
        switch customAction.action {
        case .addWater: "drop.fill"
        case .takeMedication: "pills.fill"
        case .recordMood: "face.smiling"
        default: "bolt.fill"
        }
    }

    private func performCustomAction() {
        if customAction.action == .takeMedication,
           let itemId = customAction.itemId,
           let item = routineItems.first(where: { $0.id == itemId }) {
            performRoutineAction(item)
            return
        }
        session.send(WatchEvent(action: customAction.action, value: customAction.value, itemId: customAction.itemId))
        WKInterfaceDevice.current().play(.success)
    }

    private func performRoutineAction(_ item: WatchRoutineItem) {
        if item.action == .takeMedication, !item.completed, medicationPeriodDoesNotMatch(item) {
            pendingMedicationItem = item
            return
        }
        sendRoutineAction(item)
    }

    private func sendRoutineAction(_ item: WatchRoutineItem) {
        session.send(WatchEvent(action: item.action, itemId: item.id))
        WKInterfaceDevice.current().play(.click)
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
                .multilineTextAlignment(.center)
            Text("Your routine list and actions will unlock automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("truthBeforeTasksLock")
    }

    private func sectionTitle(_ section: String) -> String {
        switch section {
        case "morning": "Morning"
        case "evening": "Evening"
        default: "Day"
        }
    }
}
