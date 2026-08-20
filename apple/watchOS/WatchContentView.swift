import SwiftUI

struct WatchContentView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var mood = 5.0

    var body: some View {
        NavigationStack {
            List {
                if let context = session.context {
                    Section("Today") {
                        Text("\(context.completed) of \(context.total) complete")
                        if let next = context.nextItemName {
                            Text("Next: \(next)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Quick actions") {
                    Button(WatchQuickAction.completeNext.title) {
                        session.send(WatchEvent(action: .completeNext))
                    }
                    Button(WatchQuickAction.addWater.title) {
                        session.send(WatchEvent(action: .addWater, value: 1))
                    }
                }

                Section("Mood") {
                    Slider(value: $mood, in: 0...10, step: 1)
                    Button("Save mood \(Int(mood))") {
                        session.send(WatchEvent(action: .recordMood, value: mood))
                    }
                }
            }
            .navigationTitle("Routine")
        }
    }
}
