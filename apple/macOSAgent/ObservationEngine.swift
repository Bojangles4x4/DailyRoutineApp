import Foundation

struct ObservationEngine {
    func analyze(events: [AgentEvent], now: Date = Date()) -> [Observation] {
        var observations: [Observation] = []
        observations.append(contentsOf: repeatedAppRevisits(events: events, now: now))
        observations.append(contentsOf: repeatedAppSequences(events: events, now: now))
        observations.append(contentsOf: missedRoutines(events: events, now: now))
        observations.append(contentsOf: recurringFollowUps(events: events, now: now))
        if let correlation = scheduleRoutineCorrelation(events: events, now: now) { observations.append(correlation) }
        return observations.sorted { $0.score > $1.score }
    }

    private func repeatedAppRevisits(events: [AgentEvent], now: Date) -> [Observation] {
        let recent = events.filter { isAnalyzableAppEvent($0, now: now) }
        return Dictionary(grouping: recent, by: \.title)
            .filter { $0.value.count >= 6 }
            .map { title, matches in
                makeObservation(
                    kind: "repeated_project_revisit",
                    key: title,
                    title: "Repeated revisits to \(title)",
                    evidence: ["\(matches.count) foreground visits in the last 7 days."],
                    score: min(10, 4 + Double(matches.count) / 2),
                    events: matches,
                    now: now
                )
            }
    }

    private func repeatedAppSequences(events: [AgentEvent], now: Date) -> [Observation] {
        let recent = events
            .filter { isAnalyzableAppEvent($0, now: now) }
            .sorted { $0.occurredAt < $1.occurredAt }
        guard recent.count > 1 else { return [] }
        var pairs: [String: [AgentEvent]] = [:]
        for index in 1..<recent.count {
            let first = recent[index - 1]
            let second = recent[index]
            guard first.title != second.title, second.occurredAt.timeIntervalSince(first.occurredAt) <= 20 * 60 else { continue }
            pairs["\(first.title) → \(second.title)", default: []].append(contentsOf: [first, second])
        }
        return pairs.filter { $0.value.count >= 6 }.map { pair, matches in
            makeObservation(
                kind: "repeated_manual_workflow",
                key: pair,
                title: "Repeated workflow: \(pair)",
                evidence: ["This app-to-app sequence appeared at least \(matches.count / 2) times in the last 7 days."],
                score: min(10, 5 + Double(matches.count / 2)),
                events: Array(Dictionary(grouping: matches, by: \.id).values.compactMap(\.first)),
                now: now
            )
        }
    }

    private func isAnalyzableAppEvent(_ event: AgentEvent, now: Date) -> Bool {
        guard event.source == .appActivity,
              event.occurredAt >= now.addingTimeInterval(-7 * 86_400)
        else { return false }

        let bundleID = event.metadata["bundleID"]?.lowercased() ?? ""
        let title = event.title.lowercased()
        let ignoredBundleIDs: Set<String> = [
            "com.apple.loginwindow",
            "com.apple.securityagent",
            "com.apple.securityagenthelper.arm64",
            "com.apple.coreservices.uiagent",
            "com.apple.usernotificationcenter",
            "com.bojangles4x4.dailyroutine.agent"
        ]
        let ignoredTitles: Set<String> = [
            "loginwindow",
            "securityagent",
            "securityagenthelper",
            "coreservicesuiagent",
            "usernotificationcenter",
            "daily routine agent"
        ]
        return !ignoredBundleIDs.contains(bundleID) && !ignoredTitles.contains(title)
    }

    private func missedRoutines(events: [AgentEvent], now: Date) -> [Observation] {
        let missed = events.filter {
            $0.source == .dailyRoutine &&
            $0.category == .routine &&
            $0.occurredAt >= now.addingTimeInterval(-14 * 86_400) &&
            $0.metadata["completed"] == "false" &&
            $0.metadata["excused"] != "true"
        }
        return Dictionary(grouping: missed, by: \.title)
            .filter { $0.value.count >= 2 }
            .map { title, matches in
                makeObservation(
                    kind: "missed_routine",
                    key: title,
                    title: "\(title) is repeatedly missed",
                    evidence: ["Not completed on \(matches.count) of the last 14 recorded days."],
                    score: min(10, 5 + Double(matches.count)),
                    events: matches,
                    now: now
                )
            }
    }

    private func recurringFollowUps(events: [AgentEvent], now: Date) -> [Observation] {
        let terms = ["follow up", "follow-up", "remind", "remember", "don't forget", "can you", "could you", "need to"]
        let matches = events.filter { event in
            guard event.source == .messages, event.occurredAt >= now.addingTimeInterval(-14 * 86_400) else { return false }
            let text = event.summary.lowercased()
            return terms.contains { text.contains($0) }
        }
        guard matches.count >= 2 else { return [] }
        return [makeObservation(
            kind: "recurring_follow_up",
            key: matches.map(\.externalID).joined(separator: "-"),
            title: "Follow-ups are accumulating in Messages",
            evidence: matches.prefix(3).map { String($0.summary.prefix(120)) },
            score: min(10, 6 + Double(matches.count) / 2),
            events: matches,
            now: now
        )]
    }

    private func scheduleRoutineCorrelation(events: [AgentEvent], now: Date) -> Observation? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let recent = events.filter { $0.occurredAt >= now.addingTimeInterval(-14 * 86_400) }
        let calendarByDay = Dictionary(grouping: recent.filter { $0.source == .calendar }, by: { formatter.string(from: $0.occurredAt) })
        let missedByDay = Dictionary(grouping: recent.filter { $0.source == .dailyRoutine && $0.metadata["completed"] == "false" && $0.metadata["excused"] != "true" }, by: { $0.metadata["date"] ?? formatter.string(from: $0.occurredAt) })
        let overlappingDays = Set(calendarByDay.filter { $0.value.count >= 4 }.keys).intersection(missedByDay.keys)
        guard overlappingDays.count >= 2 else { return nil }
        let related = overlappingDays.flatMap { (calendarByDay[$0] ?? []) + (missedByDay[$0] ?? []) }
        return makeObservation(
            kind: "schedule_routine_correlation",
            key: overlappingDays.sorted().joined(separator: "-"),
            title: "Busy calendar days coincide with missed routines",
            evidence: overlappingDays.sorted().map { day in
                "\(day): \(calendarByDay[day]?.count ?? 0) calendar events and \(missedByDay[day]?.count ?? 0) missed routines."
            },
            score: min(10, 6 + Double(overlappingDays.count)),
            events: related,
            now: now
        )
    }

    private func makeObservation(kind: String, key: String, title: String, evidence: [String], score: Double, events: [AgentEvent], now: Date) -> Observation {
        let window = Int(now.timeIntervalSince1970 / (3 * 86_400))
        return Observation(
            id: "observation-\(StableID.make(kind, key, String(window)))",
            createdAt: now,
            kind: kind,
            title: title,
            evidence: evidence,
            score: score,
            eventIDs: events.map(\.id)
        )
    }
}

struct RecommendationEngine {
    func generate(from observations: [Observation], now: Date = Date(), limit: Int = 3) -> [Recommendation] {
        Array(observations.sorted { $0.score > $1.score }.prefix(max(1, min(3, limit)))).map { observation in
            let content = content(for: observation)
            return Recommendation(
                id: "recommendation-\(observation.id)",
                observationID: observation.id,
                createdAt: now,
                pattern: observation.title,
                evidence: observation.evidence.joined(separator: "\n"),
                recommendedChange: content.change,
                whereItBelongs: content.location,
                expectedBenefit: content.benefit,
                status: .open,
                selectedAction: nil,
                actionNote: nil
            )
        }
    }

    private func content(for observation: Observation) -> (change: String, location: String, benefit: String) {
        switch observation.kind {
        case "missed_routine":
            return (
                "Move this item to a more realistic time window or add a single timely reminder.",
                "Daily Routine · Routine and schedule",
                "Reduce repeated misses without adding more daily noise."
            )
        case "recurring_follow_up":
            return (
                "Create one review queue for follow-ups instead of leaving them distributed across conversations.",
                "Daily Routine · Notes / Action items",
                "Keep commitments visible while avoiding a notification for every message."
            )
        case "repeated_manual_workflow":
            return (
                "Capture the repeated steps and stage a small automation for explicit approval.",
                "Personal Systems Agent · Automations",
                "Save repeated context switching while retaining control over external changes."
            )
        case "schedule_routine_correlation":
            return (
                "Use a lighter routine template on meeting-heavy days.",
                "Daily Routine · Day type",
                "Protect the essentials on constrained days and make completion targets more realistic."
            )
        default:
            return (
                "Create a named project or shortcut for this recurring work and review it as one unit.",
                "Daily Routine · Projects",
                "Reduce repeated setup time and make the work easier to resume."
            )
        }
    }
}
