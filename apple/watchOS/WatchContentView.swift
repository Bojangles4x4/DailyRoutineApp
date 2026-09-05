import SwiftUI

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var isCapturing = false
    @State private var pendingMedicationItem: WatchRoutineItem?

    private var progress: Double {
        guard let context = session.context, context.total > 0 else { return 0 }
        return min(max(Double(context.completed) / Double(context.total), 0), 1)
    }

    private var truthBeforeTasksComplete: Bool {
        session.context?.truthBeforeTasksComplete == true
    }

    private var routineItems: [WatchRoutineItem] {
        session.context?.items ?? []
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

            VStack(spacing: 5) {
                summaryHeader

                if truthBeforeTasksComplete {
                    routineList
                    actionBar
                } else {
                    truthLockCard
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 7)
            .padding(.top, 7)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // watchOS reserves the full clock band even though the clock only
            // occupies its trailing edge. Use the open leading side for our
            // compact summary, while keeping the clock's area clear.
            .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(isPresented: $isCapturing) {
            WatchCaptureView { text, noteType in
                session.send(WatchEvent(action: .captureNote, text: text, noteType: noteType))
            }
        }
        .alert(item: $pendingMedicationItem) { item in
            Alert(
                title: Text("Check medication time"),
                message: Text(medicationConfirmationMessage(item)),
                primaryButton: .cancel(),
                secondaryButton: .default(Text("Log now")) {
                    sendRoutineAction(item)
                }
            )
        }
    }

    private var summaryHeader: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("Today")
                    .font(.system(size: 11, weight: .bold))
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
            .padding(.leading, 9)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.teal.opacity(0.4))
                    Capsule()
                        .fill(Color.mint)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .padding(.leading, 3)
            .padding(.trailing, 42)
            .accessibilityLabel("Routine progress")
            .accessibilityValue("\(session.context?.completed ?? 0) of \(session.context?.total ?? 0) complete")
        }
    }

    private var routineList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if routineItems.isEmpty {
                    Text("No Watch-ready routines today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ForEach(routineItems) { item in
                        routineButton(item)
                    }
                }

                if let deliveryStatus = session.deliveryStatus {
                    Text(deliveryStatus)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func routineButton(_ item: WatchRoutineItem) -> some View {
        Button {
            performRoutineAction(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.completed ? Color.mint : Color.secondary)
                    .font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(sectionTitle(item.section))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(item.completed ? 0.06 : 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .controlSize(.mini)
        .accessibilityIdentifier("routine-\(item.id)")
        .accessibilityLabel(item.completed ? "\(item.name), completed" : item.name)
        .accessibilityHint(item.completed ? "Tap to reopen" : "Tap to complete")
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            compactAction(
                title: customAction.title,
                systemImage: customActionIcon,
                color: .cyan,
                identifier: "customWatchAction"
            ) {
                performCustomAction()
            }

            compactAction(
                title: "Capture",
                systemImage: "mic.fill",
                color: .mint,
                identifier: "captureWatchNote"
            ) {
                isCapturing = true
            }
        }
    }

    private func compactAction(
        title: String,
        systemImage: String,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(color.opacity(0.88), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
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
        if
            customAction.action == .takeMedication,
            let itemId = customAction.itemId,
            let item = routineItems.first(where: { $0.id == itemId })
        {
            performRoutineAction(item)
            return
        }
        session.send(WatchEvent(action: customAction.action, value: customAction.value, itemId: customAction.itemId))
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
                .accessibilityHidden(true)
            Text("Complete Morning Foundation on iPhone")
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

private struct WatchCaptureView: View {
    enum CaptureType: String, CaseIterable, Identifiable {
        case general
        case prayer
        case action

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "Note"
            case .prayer: "Prayer"
            case .action: "Action item"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var type = CaptureType.general
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Save as", selection: $type) {
                    ForEach(CaptureType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                TextField("Speak or type…", text: $text, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("watchCaptureText")

                Button("Save \(type.title)") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed, type.rawValue)
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveWatchCapture")
            }
            .navigationTitle("Capture")
        }
    }
}
