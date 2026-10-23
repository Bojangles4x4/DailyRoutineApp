import SwiftUI
import WatchKit

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var pendingMedicationItem: WatchRoutineItem?
    @State private var showAllTasks = false

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
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.13, blue: 0.17), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("Today").font(.system(size: 11, weight: .bold))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)
                Text("\(session.context?.completed ?? 0)/\(session.context?.total ?? 0)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(session.isReachable ? Color.green : Color.orange)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(session.isReachable ? "Live" : "Will sync")
                Spacer(minLength: 42)
            }
            .padding(.leading, 7)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.teal.opacity(0.4))
                    Capsule().fill(Color.mint).frame(width: proxy.size.width * progress)
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
                HStack {
                    Text("SUGGESTED FOCUS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stepsSummary
                }

                if let item = suggestedItem {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(2)
                        Text(sectionTitle(item.section))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if item.action == .takeMedication, let medications = item.medicationList, !medications.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(medications.prefix(3)), id: \.self) { medication in
                                    Label(medication, systemImage: "pills.fill")
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        Button { performRoutineAction(item) } label: {
                            Label("Mark complete", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(Color.mint.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggestedRoutineAction")
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Label("All Watch-ready tasks complete", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.mint)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let status = session.deliveryStatus {
                    Text(status).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
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
                    .foregroundStyle(item.completed ? Color.mint : Color.secondary)
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
            .background(.white.opacity(item.completed ? 0.06 : 0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routine-\(item.id)")
        .accessibilityLabel(item.completed ? "\(item.name), completed" : item.name)
        .accessibilityHint(item.completed ? "Tap to reopen" : "Tap to complete")
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            compactAction(title: customAction.title, systemImage: customActionIcon, color: .cyan, identifier: "customWatchAction") {
                performCustomAction()
            }
            compactAction(
                title: showAllTasks ? "Focus" : "All tasks",
                systemImage: showAllTasks ? "scope" : "list.bullet",
                color: .mint,
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(color.opacity(0.88), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                .foregroundStyle(.yellow)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
