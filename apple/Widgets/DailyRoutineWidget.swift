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
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.8), Color.teal.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Today’s Routine")
        .description("See today’s progress and the next routine at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DailyRoutineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineTimelineEntry

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

    private var circularView: some View {
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

    private var inlineView: some View {
        Label(
            "\(entry.snapshot.completed)/\(entry.snapshot.total) • \(entry.snapshot.nextItemName ?? "Routine")",
            systemImage: "checkmark.circle"
        )
    }

    private var rectangularView: some View {
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
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(entry.snapshot.completed) of \(entry.snapshot.total) complete")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(entry.snapshot.nextItemName.map { "Next: \($0)" } ?? "Open Daily Routine")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview(as: .accessoryRectangular) {
    DailyRoutineProgressWidget()
} timeline: {
    RoutineTimelineEntry(date: .now, snapshot: .preview)
}
