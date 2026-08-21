import SwiftUI

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var mood = 5.0

    private var progress: Double {
        guard let context = session.context, context.total > 0 else { return 0 }
        return min(max(Double(context.completed) / Double(context.total), 0), 1)
    }

    private var truthBeforeTasksComplete: Bool {
        session.context?.truthBeforeTasksComplete == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.72), Color.black, Color.teal.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        statusHeader
                        progressCard
                        if truthBeforeTasksComplete {
                            quickActions
                            moodCard
                        } else {
                            truthLockCard
                        }

                        if let deliveryStatus = session.deliveryStatus {
                            Label(
                                deliveryStatus,
                                systemImage: session.isReachable ? "iphone.and.arrow.forward" : "clock.arrow.circlepath"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
            Text("Today")
                .font(.headline)
            Spacer(minLength: 4)
            Circle()
                .fill(session.isReachable ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(session.isReachable ? "Live" : "Will sync")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var progressCard: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.mint, .cyan], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -1) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("done")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Routine progress")
            .accessibilityValue("\(session.context?.completed ?? 0) of \(session.context?.total ?? 0) complete")

            VStack(alignment: .leading, spacing: 4) {
                Text("\(session.context?.completed ?? 0) of \(session.context?.total ?? 0)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(
                    truthBeforeTasksComplete
                        ? session.context?.nextItemName.map { "Next: \($0)" } ?? "Today’s routine is complete"
                        : "Begin with Truth Before Tasks on iPhone"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let message = session.context?.lastActionMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.mint)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var truthLockCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("Complete Truth Before Tasks on iPhone")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Quick actions will unlock as soon as today’s opening is complete.")
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

    private var quickActions: some View {
        VStack(spacing: 8) {
            Button {
                session.send(WatchEvent(action: .completeNext))
            } label: {
                Label("Complete next", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(.mint)
            .disabled(session.context?.canCompleteNext != true)

            Button {
                session.send(WatchEvent(action: .addWater, value: 1))
            } label: {
                Label("Water +1", systemImage: "drop.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(.cyan)
        }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Mood", systemImage: "face.smiling")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(mood)) / 10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $mood, in: 0...10, step: 1)
                .tint(.yellow)
                .accessibilityLabel("Mood rating")

            Button("Save mood \(Int(mood))") {
                session.send(WatchEvent(action: .recordMood, value: mood))
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(.yellow)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
