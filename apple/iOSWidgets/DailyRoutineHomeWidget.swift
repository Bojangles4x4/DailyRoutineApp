import SwiftUI
import WidgetKit

@main
struct DailyRoutineHomeWidgetBundle: WidgetBundle {
    var body: some Widget { DailyRoutineHomeWidget() }
}

struct RoutineHomeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineHomeEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (RoutineHomeEntry) -> Void) {
        completion(context.isPreview ? .preview : RoutineHomeEntry(date: .now, snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineHomeEntry>) -> Void) {
        let now = Date()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [RoutineHomeEntry(date: now, snapshot: currentSnapshot())], policy: .after(refresh)))
    }

    private func currentSnapshot() -> RoutineSharedSnapshot? {
        guard let snapshot = try? RoutineSharedStateStore().loadSnapshot(),
              snapshot.localDateKey == RoutineHomeEntry.localDateKey(),
              snapshot.timeZoneIdentifier == TimeZone.current.identifier else { return nil }
        return snapshot
    }
}

struct DailyRoutineHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RoutineHomeWidgetConstants.kind, provider: RoutineHomeTimelineProvider()) { entry in
            RoutineHomeWidgetView(entry: entry)
                .containerBackground(RoutineHomeWidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Today’s Rhythm")
        .description("Your routine, earned minutes, daily steps, and quick actions.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemLarge) {
    DailyRoutineHomeWidget()
} timeline: {
    RoutineHomeEntry.preview
}
