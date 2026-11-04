import SwiftUI
import SwiftData
import Charts
import SteadyCore

// MARK: - Lifts and records

/// Every exercise you've logged, with its best numbers. Tap one for charts.
struct StrengthListView: View {
    @Environment(ContentStore.self) private var store
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt != nil }, sort: \WorkoutLog.startedAt, order: .reverse)
    private var logs: [WorkoutLog]

    private func name(_ id: String) -> String { store.content?.library[id]?.name ?? id }

    private var setsByExercise: [String: [StatSet]] {
        var out: [String: [StatSet]] = [:]
        for log in logs {
            for s in log.sets { out[s.exerciseId, default: []].append(StatSet(date: log.startedAt, weight: s.weight, reps: s.reps)) }
        }
        return out
    }

    var body: some View {
        let grouped = setsByExercise
        let ids = grouped.keys.sorted { name($0) < name($1) }
        List {
            if ids.isEmpty {
                Text("Finish a workout and your lifts appear here, with charts and personal records.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            }
            ForEach(ids, id: \.self) { id in
                let sessions = ExerciseStats.sessions(grouped[id] ?? [])
                let best = ExerciseStats.records(sessions)
                NavigationLink {
                    ExerciseProgressView(name: name(id), sessions: sessions)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(id)).foregroundStyle(Color.ink)
                            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        if let w = best.weight, w.topWeight > 0 {
                            Text("\(NumberText.format(w.topWeight)) kg").font(.subheadline.monospacedDigit()).foregroundStyle(Color.gold)
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Lifts and records")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One exercise over time, with a choice of measure and time range.
struct ExerciseProgressView: View {
    let name: String
    let sessions: [SessionStat]
    @State private var metric: StatMetric = .weight
    @State private var range: StatRange = .year

    private func text(_ s: SessionStat?, _ value: (SessionStat) -> Double, unit: String) -> String {
        guard let s, value(s) > 0 else { return "None yet" }
        return "\(NumberText.format((value(s) * 10).rounded() / 10)) \(unit) · \(s.date.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        let shown = ExerciseStats.filter(sessions, range: range)
        let records = ExerciseStats.records(sessions)
        List {
            Section {
                Picker("Measure", selection: $metric) { ForEach(StatMetric.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Range", selection: $range) { ForEach(StatRange.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
                if shown.count < 2 {
                    Text("Two or more sessions in this range draw a chart.").font(.footnote).foregroundStyle(Color.inkMuted)
                } else {
                    Chart {
                        ForEach(shown) { s in
                            LineMark(x: .value("Date", s.date), y: .value(metric.label, metric.value(s)))
                                .foregroundStyle(Color.gold).interpolationMethod(.monotone)
                            PointMark(x: .value("Date", s.date), y: .value(metric.label, metric.value(s)))
                                .foregroundStyle(Color.gold)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .accessibilityLabel("\(name) \(metric.label) chart")
                }
            } footer: {
                if metric == .oneRepMax { Text("Estimated from sets of up to 12 reps. It's a guide, not a tested max.") }
            }
            Section("Personal records") {
                LabeledContent("Heaviest weight", value: text(records.weight, { $0.topWeight }, unit: "kg"))
                LabeledContent("Best estimated 1RM", value: text(records.oneRepMax, { $0.estimatedOneRepMax }, unit: "kg"))
            }
            Section("Sessions") {
                ForEach(sessions.reversed()) { s in
                    HStack {
                        Text(s.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(NumberText.format(s.topWeight)) kg · best \(s.bestReps) reps").font(.footnote.monospacedDigit()).foregroundStyle(Color.inkMuted)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout history

struct WorkoutHistoryView: View {
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt != nil }, sort: \WorkoutLog.startedAt, order: .reverse)
    private var logs: [WorkoutLog]
    @State private var month = Date.now

    private var cal: Calendar { Calendar.current }

    private func shift(_ delta: Int) { month = cal.date(byAdding: .month, value: delta, to: month) ?? month }

    private var weekdayHeaders: [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func gridDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<count { out.append(cal.date(byAdding: .day, value: d, to: interval.start)) }
        return out
    }

    var body: some View {
        let monthLogs = logs.filter { cal.isDate($0.startedAt, equalTo: month, toGranularity: .month) }
        let trained = Set(monthLogs.map { cal.startOfDay(for: $0.startedAt) })
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("Next month")
                }
                .buttonStyle(.plain)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, h in
                        Text(String(h.prefix(1))).font(.caption2.weight(.semibold)).foregroundStyle(Color.inkMuted)
                    }
                    ForEach(Array(gridDays().enumerated()), id: \.offset) { _, day in
                        if let day {
                            let did = trained.contains(day)
                            Text("\(cal.component(.day, from: day))")
                                .font(.footnote.monospacedDigit().weight(did ? .bold : .regular))
                                .foregroundStyle(did ? Color.night : Color.ink)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(did ? Color.gold : Color.clear, in: Circle())
                                .accessibilityLabel(did ? "\(day.formatted(date: .long, time: .omitted)), trained" : day.formatted(date: .long, time: .omitted))
                        } else {
                            Color.clear.frame(height: 32)
                        }
                    }
                }
            }
            Section("Sessions this month: \(monthLogs.count)") {
                if monthLogs.isEmpty { Text("No finished workouts this month.").font(.footnote).foregroundStyle(Color.inkMuted) }
                ForEach(monthLogs) { log in
                    NavigationLink { WorkoutDetailView(log: log) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(log.workoutName).foregroundStyle(Color.ink)
                                Text(log.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Color.inkMuted)
                            }
                            Spacer()
                            Text("\(log.sets.count) sets").font(.caption).foregroundStyle(Color.inkMuted)
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Workout history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutDetailView: View {
    let log: WorkoutLog
    @Environment(ContentStore.self) private var store

    private func name(_ id: String) -> String { store.content?.library[id]?.name ?? id }

    private var exerciseIds: [String] {
        let firstSlot = Dictionary(grouping: log.sets, by: \.exerciseId).mapValues { $0.map(\.slotOrder).min() ?? 0 }
        return firstSlot.keys.sorted { (firstSlot[$0] ?? 0, $0) < (firstSlot[$1] ?? 0, $1) }
    }

    private func sets(for id: String) -> [SetLog] {
        log.sets.filter { $0.exerciseId == id }.sorted { $0.setIndex < $1.setIndex }
    }

    var body: some View {
        let volume = log.sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        List {
            Section {
                LabeledContent("Started", value: log.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let end = log.finishedAt {
                    LabeledContent("Length", value: "\(max(1, Int(end.timeIntervalSince(log.startedAt) / 60))) min")
                }
                LabeledContent("Sets", value: "\(log.sets.count)")
                LabeledContent("Total volume", value: "\(Int(volume.rounded()).formatted()) kg")
                if log.version != .standard { LabeledContent("Version", value: log.version.label) }
            }
            ForEach(exerciseIds, id: \.self) { id in
                Section(name(id)) {
                    ForEach(sets(for: id)) { s in
                        HStack {
                            Text("Set \(s.setIndex + 1)").foregroundStyle(Color.inkMuted)
                            Spacer()
                            Text("\(NumberText.format(s.weight)) kg × \(s.reps)" + (s.rpe.map { " @\(NumberText.format($0))" } ?? ""))
                                .font(.body.monospacedDigit())
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle(log.workoutName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
