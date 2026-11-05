import SwiftUI
import SwiftData
import SteadyCore

/// The week in one page: training, food, weight, and a few plain observations.
struct WeeklySummaryView: View {
    @Environment(ContentStore.self) private var store
    @Query private var logs: [WorkoutLog]
    @Query private var foods: [FoodEntry]
    @Query(sort: \CheckInEntry.date) private var checkIns: [CheckInEntry]
    @Query private var nutrition: [NutritionPlan]
    @Query private var plans: [TrainingPlan]
    @Query private var profiles: [UserProfile]
    @State private var weeksBack = 0

    private var range: (start: Date, end: Date) { VolumeReport.weekRange(containing: .now, weeksBack: weeksBack) }

    private func facts() -> WeekFacts {
        let (start, end) = range
        let cal = Calendar.current
        var f = WeekFacts()
        f.goal = profiles.first?.goal
        f.plannedSessions = plans.first?.daysPerWeek ?? 0

        // Training
        let weekLogs = logs.filter { $0.startedAt >= start && $0.startedAt < end }
        f.sessions = weekLogs.filter { $0.finishedAt != nil }.count
        let weekSets = weekLogs.flatMap(\.sets)
        f.sets = weekSets.count
        f.volumeKg = weekSets.reduce(0) { $0 + $1.weight * Double($1.reps) }

        // Records: a better top weight or estimated 1RM than anything before this week.
        let library = store.content?.library ?? [:]
        var names: [String] = []
        for id in Set(weekSets.map(\.exerciseId)) {
            let all = logs.flatMap(\.sets).filter { $0.exerciseId == id && $0.weight > 0 }
                .map { StatSet(date: $0.completedAt, weight: $0.weight, reps: $0.reps) }
            let before = ExerciseStats.sessions(all.filter { $0.date < start })
            guard !before.isEmpty else { continue }
            let during = ExerciseStats.sessions(all.filter { $0.date >= start && $0.date < end })
            let oldWeight = before.map(\.topWeight).max() ?? 0
            let oldOneRM = before.map(\.estimatedOneRepMax).max() ?? 0
            let better = during.contains { $0.topWeight > oldWeight || $0.estimatedOneRepMax > oldOneRM }
            if better, let name = library[id]?.name { names.append(name) }
        }
        f.records = Array(names.sorted().prefix(5))

        // Food
        let weekFood = foods.filter { $0.eatenAt >= start && $0.eatenAt < end }
        let byDay = Dictionary(grouping: weekFood) { cal.startOfDay(for: $0.eatenAt) }
        f.foodDays = byDay.count
        if let n = nutrition.first {
            f.kcalTarget = n.calories
            f.proteinTarget = n.protein
            f.daysProteinHit = byDay.values.filter { day in
                day.reduce(0) { $0 + $1.protein } >= Double(n.protein) * WeekSummary.proteinHitShare
            }.count
        }
        if !byDay.isEmpty {
            f.avgKcal = byDay.values.map { $0.reduce(0) { $0 + $1.kcal } }.reduce(0, +) / Double(byDay.count)
            f.avgProtein = byDay.values.map { $0.reduce(0) { $0 + $1.protein } }.reduce(0, +) / Double(byDay.count)
        }

        // Weight, from check-ins
        func average(_ from: Date, _ to: Date) -> Double? {
            let w = checkIns.filter { $0.date >= from && $0.date < to }.compactMap(\.weightKg)
            return w.isEmpty ? nil : w.reduce(0, +) / Double(w.count)
        }
        f.weightThisWeek = average(start, end)
        let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
        f.weightPrevious = average(prevStart, start)
        return f
    }

    var body: some View {
        let f = facts()
        List {
            Section {
                Picker("Week", selection: $weeksBack) {
                    Text("This week").tag(0)
                    Text("Last week").tag(1)
                    Text("2 weeks ago").tag(2)
                    Text("3 weeks ago").tag(3)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("summaryWeek")
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(range.start.formatted(.dateTime.day().month(.abbreviated))) to \(range.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.gold)
                    Text(WeekSummary.headline(f)).font(.title2.weight(.bold))
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            Section("Training") {
                stat("Sessions", f.plannedSessions > 0 ? "\(f.sessions) of \(f.plannedSessions)" : "\(f.sessions)")
                stat("Sets logged", "\(f.sets)")
                stat("Volume lifted", f.volumeKg > 0 ? "\(Int(f.volumeKg.rounded()).formatted()) kg" : "-")
            }
            Section("Food") {
                stat("Days logged", "\(f.foodDays) of 7")
                stat("Average calories", f.avgKcal.map { "\(Int($0.rounded()))" + (f.kcalTarget.map { " / \($0)" } ?? "") } ?? "-")
                stat("Average protein", f.avgProtein.map { "\(Int($0.rounded())) g" + (f.proteinTarget.map { " / \($0) g" } ?? "") } ?? "-")
                if let w = f.weightThisWeek { stat("Average weight", String(format: "%.1f kg", w)) }
            }
            Section {
                ForEach(WeekSummary.notes(f), id: \.self) { Text($0).font(.callout) }
            } header: { Text("What stands out") } footer: {
                Text("Observations from your own logs, not medical advice. One week is a small sample, so look for patterns over several weeks.")
            }
        }
        .themedList()
        .navigationTitle("Weekly summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit() }
    }
}
