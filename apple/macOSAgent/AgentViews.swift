import SwiftUI

struct AgentRootView: View {
    @EnvironmentObject private var model: AgentViewModel
    @State private var selection: AgentViewModel.Pane = .inbox

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AgentViewModel.Pane.allCases) { pane in
                    Button {
                        selection = pane
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                selection == pane ? Color.accentColor.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == pane ? .isSelected : [])
                }
                Spacer()
            }
            .padding(8)
            .navigationTitle("Daily Routine")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch selection {
                case .inbox: RecommendationInboxView()
                case .diagnostics: DiagnosticsView()
                case .privacy: PrivacyBoundaryView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let banner = model.banner {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                        Text(banner).lineLimit(2)
                        Spacer()
                        Button("Dismiss") { model.banner = nil }
                    }
                    .font(.callout)
                    .padding(12)
                    .background(.regularMaterial)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 620)
    }
}

struct RecommendationInboxView: View {
    @EnvironmentObject private var model: AgentViewModel

    private var active: [Recommendation] {
        model.recommendations.filter { [.open, .staged, .watching].contains($0.status) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommendation inbox").font(.largeTitle.bold())
                        Text("Only the top 1–3 recommendations are created per 72-hour review. Collection and observation passes stay quiet.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.runNow() }
                    } label: {
                        Label(model.isWorking ? "Running…" : "Run review now", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                }

                if active.isEmpty {
                    ContentUnavailableView(
                        "No recommendations yet",
                        systemImage: "tray",
                        description: Text("Connect a source or load test data in Diagnostics, then run a review.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    ForEach(active.prefix(3)) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }

                let archived = model.recommendations.filter { !active.map(\.id).contains($0.id) }
                if !archived.isEmpty {
                    DisclosureGroup("Resolved recommendations (\(archived.count))") {
                        ForEach(archived) { item in
                            HStack {
                                Text(item.pattern)
                                Spacer()
                                Text(item.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .navigationTitle("Inbox")
    }
}

private struct RecommendationCard: View {
    @EnvironmentObject private var model: AgentViewModel
    let recommendation: Recommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Recommendation", systemImage: "lightbulb.max.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                if recommendation.status != .open {
                    Text(recommendation.status.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            recommendationField("Pattern noticed", recommendation.pattern)
            recommendationField("Evidence", recommendation.evidence)
            recommendationField("Recommended change", recommendation.recommendedChange)
            HStack(alignment: .top, spacing: 28) {
                recommendationField("Where it belongs", recommendation.whereItBelongs)
                recommendationField("Expected benefit", recommendation.expectedBenefit)
            }
            Divider()
            Text("Choose an action").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(RecommendationAction.allCases) { action in
                    Button(action.title) { model.perform(action, on: recommendation) }
                        .buttonStyle(.bordered)
                        .tint(action.requiresFuturePermission ? .accentColor : .secondary)
                        .controlSize(.small)
                }
            }
            if let note = recommendation.actionNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.45)))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    @ViewBuilder
    private func recommendationField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AgentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics").font(.largeTitle.bold())
                Text("Connection health, local event counts, and recent background jobs.")
                    .foregroundStyle(.secondary)

                Text("Data sources").font(.headline)
                ForEach(model.diagnostics) { diagnostic in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(diagnostic.source.title).fontWeight(.semibold)
                            Spacer()
                            Text("\(diagnostic.eventCount) events").font(.caption.monospacedDigit())
                        }
                        Text(diagnostic.permission.title)
                            .font(.caption)
                            .foregroundStyle(diagnostic.permission == .connected ? .green : .secondary)
                        Text(diagnostic.detail).font(.caption).foregroundStyle(.secondary)
                        Text(diagnostic.lastSuccessfulRead.map {
                            "Last read \($0.formatted(date: .abbreviated, time: .shortened))"
                        } ?? "Last read: never")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        sourceActions(for: diagnostic)
                            .padding(.top, 3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }

                Text("Recent jobs").font(.headline).padding(.top, 4)
                if model.jobs.isEmpty {
                    Text("No jobs have run yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.jobs.prefix(6)) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(job.succeeded ? "Completed" : "Failed"): \(job.job.capitalized)")
                                .fontWeight(.semibold)
                            Text(job.detail).font(.caption).foregroundStyle(.secondary)
                            Text(job.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Button(model.launchAtLoginEnabled ? "Disable launch at login" : "Enable launch at login") {
                        model.setLaunchAtLogin(!model.launchAtLoginEnabled)
                    }
                    Button(model.isWorking ? "Running…" : "Run all jobs now") {
                        Task { await model.runNow() }
                    }
                    .disabled(model.isWorking)
                    Button("Reveal local database") { model.revealDatabase() }
                }
            }
            .padding(24)
        }
        .navigationTitle("Diagnostics")
    }

    @ViewBuilder
    private func sourceActions(for diagnostic: SourceDiagnostic) -> some View {
        switch diagnostic.source {
        case .messages:
            HStack {
                Button(diagnostic.enabled ? "Disable Messages" : "Enable Messages") {
                    Task { await model.setMessagesEnabled(!diagnostic.enabled) }
                }
                Button("Open Messages Importer") { model.openMessagesImporter() }
                Button("Importer Full Disk Access…") { model.openFullDiskAccessSettings() }
            }
        case .appActivity:
            Button(diagnostic.enabled ? "Stop recording app switches" : "Record foreground app switches") {
                model.setActivityEnabled(!diagnostic.enabled)
            }
        case .calendar:
            Button(diagnostic.permission == .connected ? "Refresh Calendar" : "Connect Calendar") {
                Task { await model.requestCalendarAccess() }
            }
        case .dailyRoutine:
            HStack {
                if diagnostic.enabled {
                    Button("Refresh Daily Routine") { Task { await model.refreshRoutineSnapshot() } }
                }
                Button(diagnostic.enabled ? "Choose another file…" : "Choose Daily Routine snapshot…") {
                    Task { await model.chooseRoutineSnapshot() }
                }
            }
        case .testData:
            if diagnostic.enabled {
                Button("Clear synthetic events") { model.clearTestData() }
            } else {
                Button("Load synthetic events") { Task { await model.loadTestData() } }
            }
        }
    }
}

private struct SourceDiagnosticCard: View {
    @EnvironmentObject private var model: AgentViewModel
    let diagnostic: SourceDiagnostic

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.source.title).font(.headline)
                        Text(diagnostic.permission.title)
                            .font(.caption)
                            .foregroundStyle(diagnostic.permission == .connected ? .green : .secondary)
                    }
                    Spacer()
                    Text("\(diagnostic.eventCount) events")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                Text(diagnostic.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let date = diagnostic.lastSuccessfulRead {
                    Text("Last read \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                controls
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch diagnostic.source {
        case .messages:
            HStack {
                Button(diagnostic.enabled ? "Disable" : "Enable") {
                    Task { await model.setMessagesEnabled(!diagnostic.enabled) }
                }
                Spacer()
                Button("Open importer") { model.openMessagesImporter() }
                Button("Importer Full Disk Access…") { model.openFullDiskAccessSettings() }
            }
        case .appActivity:
            Button(diagnostic.enabled ? "Stop recording foreground app switches" : "Record foreground app switches") {
                model.setActivityEnabled(!diagnostic.enabled)
            }
        case .calendar:
            Button(diagnostic.permission == .connected ? "Refresh calendar" : "Connect calendar") {
                Task { await model.requestCalendarAccess() }
            }
        case .dailyRoutine:
            HStack {
                if diagnostic.enabled {
                    Button("Refresh now") { Task { await model.refreshRoutineSnapshot() } }
                }
                Button(diagnostic.enabled ? "Choose another file…" : "Choose snapshot…") {
                    Task { await model.chooseRoutineSnapshot() }
                }
            }
        case .testData:
            if diagnostic.enabled {
                Button("Clear synthetic events") { model.clearTestData() }
            } else {
                Button("Load synthetic events") { Task { await model.loadTestData() } }
            }
        }
    }
}

struct PrivacyBoundaryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy boundaries").font(.largeTitle.bold())
                Text("The MVP is deliberately local-first. It does not contain a network client or model API integration.")
                    .font(.title3)
                privacyRow("Raw data stays on this Mac", "The separate Messages importer writes one owner-only local snapshot. The Agent stores imported Messages, calendar details, app activity, and Daily Routine history only in local SQLite.", "externaldrive.badge.lock")
                privacyRow("Sources are opt-in", "Messages, app activity, Calendar, and the Daily Routine snapshot remain off until you explicitly connect each one.", "checkmark.shield")
                privacyRow("Full Disk Access is isolated", "Only Daily Routine Messages Importer should receive Full Disk Access. The main Agent reads the helper snapshot and remains unprivileged.", "lock.shield")
                privacyRow("No surveillance claims", "App activity means foreground application switches. This MVP does not read Screen Time, browser URLs, window titles, keystrokes, or screen contents.", "eye.slash")
                privacyRow("No external changes", "Recommendation buttons can stage an action, but the MVP never sends a message, edits a calendar event, creates a cloud project, or changes the iPhone app automatically.", "hand.raised")
                privacyRow("Derived-only model boundary", "If a model layer is added later, the integration point is the observation and recommendation layer—not raw Messages or browsing/activity rows—and it must require separate approval.", "brain.head.profile")
                Divider()
                Text("Sensitivity levels").font(.headline)
                Text("Low: operational metadata · Personal: routine/app patterns · Sensitive: calendar details · Restricted: message content. Sensitivity is stored with every event so future export or model policies can enforce the boundary.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
        }
        .navigationTitle("Privacy")
    }

    private func privacyRow(_ title: String, _ body: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 30).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
