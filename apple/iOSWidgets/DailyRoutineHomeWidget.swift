import SwiftUI
import WidgetKit

@main
struct DailyRoutineHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyRoutineHomeWidget()
    }
}

struct RoutineHomeEntry: TimelineEntry {
    let date: Date
    let snapshot: RoutineSharedSnapshot?

    static let preview = RoutineHomeEntry(
        date: .now,
        snapshot: RoutineSharedSnapshot(
            schemaVersion: RoutineSharedSnapshot.currentSchemaVersion,
            revision: 12,
            localDateKey: RoutineHomeTimelineProvider.localDateKey(),
            timeZoneIdentifier: TimeZone.current.identifier,
            foundationComplete: true,
            convictionsEnabled: true,
            completed: 6,
            total: 10,
            earnedAccessRemainingMinutes: 25,
            earnedAccessDailyLimitMinutes: 60,
            nextItem: RoutineSharedItemSnapshot(
                id: "preview-next",
                title: "Morning walk",
                section: "Morning",
                completed: false,
                actionID: RoutineSharedActionID.setCheckboxCompletion
            ),
            eligibleItems: [
                RoutineSharedItemSnapshot(id: "preview-next", title: "Morning walk", section: "Morning", completed: false, actionID: RoutineSharedActionID.setCheckboxCompletion),
                RoutineSharedItemSnapshot(id: "preview-plan", title: "Plan the day", section: "Morning", completed: false, actionID: RoutineSharedActionID.setCheckboxCompletion),
                RoutineSharedItemSnapshot(id: "preview-read", title: "Read for 20 minutes", section: "Afternoon", completed: false, actionID: RoutineSharedActionID.setCheckboxCompletion)
            ],
            updatedAt: ISO8601DateFormatter.bridge.string(from: .now)
        )
    )
}

struct RoutineHomeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineHomeEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineHomeEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
        } else {
            completion(RoutineHomeEntry(date: .now, snapshot: currentSnapshot()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineHomeEntry>) -> Void) {
        let now = Date()
        let entry = RoutineHomeEntry(date: now, snapshot: currentSnapshot())
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentSnapshot() -> RoutineSharedSnapshot? {
        guard
            let snapshot = try? RoutineSharedStateStore().loadSnapshot(),
            snapshot.localDateKey == Self.localDateKey(),
            snapshot.timeZoneIdentifier == TimeZone.current.identifier
        else { return nil }
        return snapshot
    }

    static func localDateKey(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct DailyRoutineHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RoutineHomeWidgetConstants.kind, provider: RoutineHomeTimelineProvider()) { entry in
            RoutineHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.055, green: 0.075, blue: 0.13), Color(red: 0.06, green: 0.16, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Today’s Rhythm")
        .description("See today’s routine and complete one eligible item.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RoutineHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineHomeEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall:
                compactView(snapshot)
            case .systemMedium:
                mediumView(snapshot)
            default:
                largeView(snapshot)
            }
        } else {
            refreshView
        }
    }

    private func compactView(_ snapshot: RoutineSharedSnapshot) -> some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot, compact: true)
                Spacer(minLength: 0)
                foundationStatus(snapshot)
                ProgressView(value: progress(snapshot))
                    .tint(.mint)
                Text("\(snapshot.completed) of \(snapshot.total) complete")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func mediumView(_ snapshot: RoutineSharedSnapshot) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot, compact: false)
                foundationStatus(snapshot)
                progressSummary(snapshot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if snapshot.foundationComplete, let item = firstIncompleteItem(snapshot) {
                taskButton(item, snapshot: snapshot, compact: true)
                    .frame(maxWidth: .infinity)
            } else {
                openAppButton(snapshot.foundationComplete ? "Open today" : "Begin on iPhone")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func largeView(_ snapshot: RoutineSharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            header(snapshot, compact: false)

            ProgressView(value: progress(snapshot))
                .tint(.mint)

            foundationStatus(snapshot)

            HStack(spacing: 8) {
                metricTile(
                    title: "Earned apps",
                    value: earnedAccessSummary(snapshot),
                    highlighted: true
                )
                .privacySensitive()
                metricTile(
                    title: "Remaining",
                    value: "\(max(0, snapshot.total - snapshot.completed)) routines"
                )
                metricTile(
                    title: "Available",
                    value: "\(snapshot.eligibleItems.filter { !$0.completed }.count) actions"
                )
            }

            if snapshot.foundationComplete {
                let items = Array(snapshot.eligibleItems.filter { !$0.completed }.prefix(3))
                if items.isEmpty {
                    completedView
                } else {
                    VStack(spacing: 8) {
                        ForEach(items, id: \.id) { item in
                            taskButton(item, snapshot: snapshot, compact: false)
                        }
                    }
                }
            } else {
                lockedFoundationView
            }

            Spacer(minLength: 0)
            HStack {
                if let updated = updatedDate(snapshot) {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Link(destination: Self.appURL) {
                    HStack(spacing: 4) {
                        Text("Open routine")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func header(_ snapshot: RoutineSharedSnapshot, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
            Text(compact ? "TODAY" : "TODAY’S RHYTHM")
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .tracking(compact ? 0.8 : 0.4)
            Spacer(minLength: 0)
            if !compact {
                Text(family == .systemLarge
                    ? "\(Int((progress(snapshot) * 100).rounded()))% · \(snapshot.completed)/\(snapshot.total)"
                    : "\(Int((progress(snapshot) * 100).rounded()))%")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.mint)
            }
        }
    }

    private func foundationStatus(_ snapshot: RoutineSharedSnapshot) -> some View {
        Label(
            foundationStatusTitle(snapshot),
            systemImage: snapshot.foundationComplete ? "checkmark.circle.fill" : "lock.shield.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(snapshot.foundationComplete ? .mint : .orange)
        .lineLimit(family == .systemSmall ? 2 : 1)
        .minimumScaleFactor(0.75)
    }

    private func foundationStatusTitle(_ snapshot: RoutineSharedSnapshot) -> String {
        guard snapshot.foundationComplete else { return "Begin Truth Before Tasks" }
        return snapshot.convictionsEnabled == true
            ? "Truth Before Tasks ✓ · Convictions ✓"
            : "Truth Before Tasks complete"
    }

    private func metricTile(title: String, value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(highlighted ? Color.mint : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func earnedAccessSummary(_ snapshot: RoutineSharedSnapshot) -> String {
        guard let minutes = snapshot.earnedAccessRemainingMinutes else { return "Open app" }
        return "\(minutes) min left"
    }

    private func updatedDate(_ snapshot: RoutineSharedSnapshot) -> Date? {
        ISO8601DateFormatter.bridgeWithFractionalSeconds.date(from: snapshot.updatedAt)
            ?? ISO8601DateFormatter.bridge.date(from: snapshot.updatedAt)
    }

    private func progressSummary(_ snapshot: RoutineSharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: progress(snapshot))
                .tint(.mint)
            Text("\(snapshot.completed) of \(snapshot.total) complete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func taskButton(_ item: RoutineSharedItemSnapshot, snapshot: RoutineSharedSnapshot, compact: Bool) -> some View {
        Button(intent: CompleteRoutineItemIntent(
            targetID: item.id,
            expectedRevision: snapshot.revision,
            localDateKey: snapshot.localDateKey,
            timeZoneIdentifier: snapshot.timeZoneIdentifier
        )) {
            HStack(spacing: 9) {
                Image(systemName: "circle")
                    .font(.headline)
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .lineLimit(compact ? 2 : 1)
                    Text(item.section)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 68 : 48, alignment: .leading)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .privacySensitive()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(item.title)")
    }

    private var lockedFoundationView: some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Begin with truth, then convictions", systemImage: "sun.horizon.fill")
                    .font(.headline)
                Text("Routine actions remain protected until Truth Before Tasks and any configured convictions are complete on iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Begin on iPhone")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var completedView: some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 8) {
                Label("All visible items complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Text("Open Daily Routine to review today or see items hidden for privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func openAppButton(_ title: String) -> some View {
        Link(destination: Self.appURL) {
            Label(title, systemImage: "arrow.up.forward.app.fill")
                .font(.caption.weight(.bold))
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var refreshView: some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title)
                    .foregroundStyle(.mint)
                Text("Open Daily Routine to refresh")
                    .font(.headline)
                Text("The widget is waiting for a current, private snapshot from the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func firstIncompleteItem(_ snapshot: RoutineSharedSnapshot) -> RoutineSharedItemSnapshot? {
        snapshot.eligibleItems.first { !$0.completed }
    }

    private func progress(_ snapshot: RoutineSharedSnapshot) -> Double {
        guard snapshot.total > 0 else { return 0 }
        return min(max(Double(snapshot.completed) / Double(snapshot.total), 0), 1)
    }

    private static let appURL = URL(string: "dailyroutine://today")!
}

#Preview(as: .systemLarge) {
    DailyRoutineHomeWidget()
} timeline: {
    RoutineHomeEntry.preview
}
