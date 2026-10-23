import SwiftUI
import UIKit
import WidgetKit

enum RoutineHomeWidgetPalette {
    static let background = adaptive(0xF5F7F9, 0x15212B)
    static let surface = adaptive(0xFFFFFF, 0x223340)
    static let ink = adaptive(0x1E3443, 0xEDF4F8)
    static let muted = adaptive(0x536979, 0xB7C9D6)
    static let accent = adaptive(0x2D678F, 0x91C4E6)
    static let onAccent = adaptive(0xFFFFFF, 0x152A39)
    static let soft = adaptive(0xE5F0F7, 0x293F50)
    static let track = adaptive(0xDBE3E8, 0x405668)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct RoutineHomeEntry: TimelineEntry {
    let date: Date
    let snapshot: RoutineSharedSnapshot?

    static func localDateKey(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static let preview = RoutineHomeEntry(date: .now, snapshot: RoutineSharedSnapshot(
        schemaVersion: 1, revision: 12, localDateKey: localDateKey(),
        timeZoneIdentifier: TimeZone.current.identifier, foundationComplete: true,
        convictionsEnabled: true, completed: 6, total: 10,
        earnedAccessRemainingMinutes: 25, earnedAccessDailyLimitMinutes: 60,
        waterItemID: "day-water", waterCurrent: 4, waterTarget: 6,
        stepCount: 5740, stepGoal: 8000,
        nextItem: RoutineSharedItemSnapshot(id: "preview-walk", title: "Morning walk", section: "Morning", completed: false, actionID: RoutineSharedActionID.setCheckboxCompletion),
        eligibleItems: [RoutineSharedItemSnapshot(id: "preview-walk", title: "Morning walk", section: "Morning", completed: false, actionID: RoutineSharedActionID.setCheckboxCompletion)],
        updatedAt: ISO8601DateFormatter.bridge.string(from: .now)
    ))
}

struct RoutineHomeWidgetView: View {
    @Environment(\.widgetFamily) private var systemFamily
    let entry: RoutineHomeEntry
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private typealias Palette = RoutineHomeWidgetPalette
    private static let appURL = URL(string: "dailyroutine://today")!

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: smallView(snapshot)
                case .systemMedium: mediumView(snapshot)
                default: largeView(snapshot)
                }
            } else { refreshView }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Palette.ink)
    }

    private func header(_ snapshot: RoutineSharedSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(family == .systemSmall ? "Today’s Rhythm" : "Daily Rhythms")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if family == .systemLarge, let updated = updatedDate(snapshot) {
                Text(updated, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel("Updated at \(updated.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    private func largeView(_ snapshot: RoutineSharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(snapshot)
            HStack(spacing: 7) {
                metric("Truth Before Tasks", value: snapshot.foundationComplete ? "Reviewed" : "Review first", primary: true)
                metric("Earned apps", value: snapshot.earnedAccessRemainingMinutes.map { "\($0)m" } ?? "Open app")
                    .privacySensitive()
                metric("Today", value: "\(Int((progress(snapshot) * 100).rounded()))%")
            }
            focusCard(snapshot)
            Spacer(minLength: 0)
            stepsSummary(snapshot)
            HStack(spacing: 8) {
                if let id = snapshot.waterItemID, let current = snapshot.waterCurrent,
                   let target = snapshot.waterTarget, snapshot.foundationComplete {
                    Button(intent: AddWaterIntent(targetID: id, expectedRevision: snapshot.revision,
                        localDateKey: snapshot.localDateKey, timeZoneIdentifier: snapshot.timeZoneIdentifier)) {
                        Label("Water +1 · \(current)/\(target)", systemImage: "drop")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(Palette.accent)
                            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .privacySensitive()
                }
                appLink("View all tasks", symbol: "list.bullet", primary: false)
            }
        }
    }

    private func metric(_ title: String, value: String, primary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(primary ? Palette.onAccent : Palette.muted)
                .frame(minHeight: 25, alignment: .topLeading)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(primary ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: 11))
    }

    private func focusCard(_ snapshot: RoutineSharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !snapshot.foundationComplete {
                Text("Begin with truth").font(.headline.weight(.medium))
                Text("Review on iPhone to begin today.").font(.caption).foregroundStyle(Palette.muted)
                appLink("Begin on iPhone", symbol: "arrow.up.forward", primary: true)
            } else if let item = snapshot.eligibleItems.first(where: { !$0.completed }) {
                HStack {
                    Text("Suggested focus").font(.caption2).foregroundStyle(Palette.muted)
                    Spacer(minLength: 2)
                    Text(item.section).font(.caption2).foregroundStyle(Palette.muted)
                }
                Text(item.title).font(.headline.weight(.medium)).lineLimit(2)
                    .privacySensitive()
                HStack(spacing: 7) {
                    appLink("Open routine", symbol: nil, primary: false)
                    completeButton(item, snapshot: snapshot)
                }
            } else {
                Text("Today’s routine").font(.caption2).foregroundStyle(Palette.muted)
                Text("Shared tasks complete").font(.headline.weight(.medium))
                appLink("Review today", symbol: "checkmark.circle", primary: false)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
    }

    private func stepsSummary(_ snapshot: RoutineSharedSnapshot) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text("Steps").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                if let count = snapshot.stepCount, let goal = snapshot.stepGoal {
                    Text("\(count.formatted()) / \(goal.formatted())")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.ink)
                        .privacySensitive()
                } else {
                    Text("Open app to refresh").font(.caption2).foregroundStyle(Palette.muted)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    if let count = snapshot.stepCount, let goal = snapshot.stepGoal, goal > 0 {
                        Capsule().fill(Palette.accent)
                            .frame(width: geometry.size.width * min(1, max(0, Double(count) / Double(goal))))
                    }
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
    }

    private func smallView(_ snapshot: RoutineSharedSnapshot) -> some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 8) {
                header(snapshot)
                Spacer(minLength: 0)
                Text(snapshot.foundationComplete ? "Truth Before Tasks ✓" : "Begin Truth Before Tasks")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.accent)
                Text("\(Int((progress(snapshot) * 100).rounded()))%")
                    .font(.title.weight(.medium)).foregroundStyle(Palette.ink)
                Text("\(snapshot.completed) of \(snapshot.total) complete")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }

    private func mediumView(_ snapshot: RoutineSharedSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header(snapshot)
                Text(snapshot.foundationComplete ? "Truth Before Tasks ✓" : "Review truth first")
                    .font(.caption2).foregroundStyle(Palette.accent)
                Text("\(snapshot.completed) of \(snapshot.total) complete")
                    .font(.caption).foregroundStyle(Palette.ink)
                if let minutes = snapshot.earnedAccessRemainingMinutes {
                    Text("Earned apps · \(minutes)m").font(.caption2).foregroundStyle(Palette.muted).privacySensitive()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if snapshot.foundationComplete, let item = snapshot.eligibleItems.first(where: { !$0.completed }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).font(.caption.weight(.medium)).foregroundStyle(Palette.ink).lineLimit(2).privacySensitive()
                    completeButton(item, snapshot: snapshot)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                appLink(snapshot.foundationComplete ? "Open today" : "Begin on iPhone", symbol: nil, primary: false)
            }
        }
    }

    private func completeButton(_ item: RoutineSharedItemSnapshot, snapshot: RoutineSharedSnapshot) -> some View {
        Button(intent: CompleteRoutineItemIntent(targetID: item.id, expectedRevision: snapshot.revision,
            localDateKey: snapshot.localDateKey, timeZoneIdentifier: snapshot.timeZoneIdentifier)) {
            Text("Mark complete").font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Palette.onAccent)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(item.title)")
    }

    private func appLink(_ title: String, symbol: String?, primary: Bool) -> some View {
        Link(destination: Self.appURL) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(primary ? Palette.onAccent : Palette.accent)
            .background(primary ? Palette.accent : Palette.soft, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var refreshView: some View {
        Link(destination: Self.appURL) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "arrow.clockwise.circle").font(.title2).foregroundStyle(Palette.accent)
                Text("Open Daily Routine to refresh").font(.headline.weight(.medium)).foregroundStyle(Palette.ink)
                Text("Refresh today’s private widget summary.").font(.caption).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func progress(_ snapshot: RoutineSharedSnapshot) -> Double {
        guard snapshot.total > 0 else { return 0 }
        return min(max(Double(snapshot.completed) / Double(snapshot.total), 0), 1)
    }

    private func updatedDate(_ snapshot: RoutineSharedSnapshot) -> Date? {
        ISO8601DateFormatter.bridgeWithFractionalSeconds.date(from: snapshot.updatedAt)
            ?? ISO8601DateFormatter.bridge.date(from: snapshot.updatedAt)
    }
}
