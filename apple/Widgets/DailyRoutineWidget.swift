import SwiftUI
import WidgetKit

@main
struct DailyRoutineWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyRoutineProgressWidget()
    }
}

struct RoutineTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: RoutineWidgetSnapshot
}

struct RoutineTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineTimelineEntry {
        RoutineTimelineEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineTimelineEntry) -> Void) {
        completion(RoutineTimelineEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineTimelineEntry>) -> Void) {
        let now = Date()
        let entry = RoutineTimelineEntry(
            date: now,
            snapshot: WidgetSnapshotStore.load() ?? RoutineWidgetSnapshot(
                completed: 0,
                total: 0,
                nextItemName: "Open Daily Routine to sync",
                lastActionMessage: nil
            )
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct DailyRoutineProgressWidget: Widget {
    let kind = WidgetSnapshotStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoutineTimelineProvider()) { entry in
            DailyRoutineWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.071, green: 0.110, blue: 0.137)
                }
                .tint(Color(red: 0.49, green: 0.75, blue: 0.93))
        }
        .configurationDisplayName("Today’s Routine")
        .description("See today’s progress and open your routine list at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyRoutineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineTimelineEntry

    private var truthIsLocked: Bool {
        !entry.snapshot.isCurrentDay || entry.snapshot.truthBeforeTasksComplete == false
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    @ViewBuilder
    private var circularView: some View {
        if truthIsLocked {
            Image(systemName: "lock.fill")
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel("Truth Before Tasks is required on iPhone")
        } else {
            Gauge(value: entry.snapshot.progress) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.snapshot.completed)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel("Routine progress")
            .accessibilityValue("\(entry.snapshot.completed) of \(entry.snapshot.total) complete")
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if truthIsLocked {
            Label("Truth Before Tasks", systemImage: "lock.fill")
        } else {
            Label(
                "\(entry.snapshot.completed)/\(entry.snapshot.total) • Routine list",
                systemImage: "checkmark.circle"
            )
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if truthIsLocked {
            HStack(spacing: 9) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Truth Before Tasks")
                        .font(.system(size: 10, weight: .medium))
                    Text(entry.snapshot.isCurrentDay ? "Begin on iPhone" : "Open iPhone to refresh")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Review Truth Before Tasks on iPhone")
        } else {
            HStack(spacing: 9) {
                Gauge(value: entry.snapshot.progress) {
                    Image(systemName: "checkmark")
                } currentValueLabel: {
                    Text("\(Int((entry.snapshot.progress * 100).rounded()))%")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested focus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(entry.snapshot.nextItemName ?? "Open routine list")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .privacySensitive()
                    Text("\(entry.snapshot.completed) of \(entry.snapshot.total) complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if targetEnvironment(simulator)
#Preview(as: .accessoryRectangular) {
    DailyRoutineProgressWidget()
} timeline: {
    RoutineTimelineEntry(date: .now, snapshot: .preview)
}
#endif
