import SwiftUI
import SwiftData
import SteadyCore

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            TrainView()
                .tabItem { Label("Train", systemImage: "dumbbell") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            ComingSoonView(title: "Progress", systemImage: "chart.xyaxis.line",
                           detail: "Weekly check-ins, measurements, photos and your weight trend arrive in a later update.")
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let detail: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
                .navigationTitle(title)
        }
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var plans: [TrainingPlan]
    @Query private var food: [NutritionPlan]
    @Query private var checkIns: [CheckInSettings]
    @Query(sort: \WorkoutLog.startedAt, order: .reverse) private var logs: [WorkoutLog]
    @Query private var foodEntries: [FoodEntry]
    @State private var startSheet = false
    @State private var activeLog: WorkoutLog?

    private var unfinished: WorkoutLog? { logs.first { $0.finishedAt == nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                            .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                        Text(greeting).font(.largeTitle.weight(.bold)).foregroundStyle(Color.ink)
                    }
                    .padding(.top, 8)

                    if let plan = plans.first, let program = store.content?.program(plan.programId) {
                        sessionCard(plan: plan, program: program)
                        WeekStrip(logs: logs, plan: plan)
                    }
                    if let n = food.first {
                        let range = Calendar.current.dayRange(.now)
                        FoodCard(plan: n, totals: totals(foodEntries.filter { $0.eatenAt >= range.0 && $0.eatenAt < range.1 }))
                    }
                    if let c = checkIns.first { CheckInCard(settings: c) }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $startSheet) {
                if let plan = plans.first, let program = store.content?.program(plan.programId),
                   let next = program.session(at: plan.nextSessionIndex) {
                    StartWorkoutSheet(program: program, week: next.week, workout: next.workout) { version in
                        start(plan: plan, program: program, week: next.week, workout: next.workout, version: version)
                    }
                }
            }
            .navigationDestination(item: $activeLog) { log in
                if let program = store.content?.program(log.programId),
                   let week = program.weeks.first(where: { $0.number == log.weekNumber }),
                   let workout = week.workouts.first(where: { $0.position == log.workoutPosition }) {
                    ActiveWorkoutView(log: log, program: program, workout: workout)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionCard(plan: TrainingPlan, program: Program) -> some View {
        if let next = program.session(at: plan.nextSessionIndex) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(unfinished == nil ? "NEXT SESSION" : "IN PROGRESS")
                        .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                    Spacer()
                    Text("WEEK \(next.week.number) OF \(program.weeks.count)")
                        .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.inkMuted)
                }
                NavigationLink {
                    WorkoutPreview(program: program, week: next.week, workout: next.workout)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(next.workout.name).font(.system(.title, design: .default).weight(.bold))
                                .foregroundStyle(Color.ink)
                            Image(systemName: "chevron.right").font(.headline).foregroundStyle(Color.inkMuted)
                        }
                        HStack(spacing: 16) {
                            Label("\(next.workout.estimatedMinutes) min", systemImage: "clock")
                            Label("\(next.workout.slots.count) exercises", systemImage: "dumbbell")
                            if let phase = next.week.phase { Label(phase, systemImage: "flag") }
                        }
                        .font(.subheadline).foregroundStyle(Color.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nextSession")
                Button {
                    if let open = unfinished { activeLog = open } else { startSheet = true }
                } label: {
                    Text(unfinished == nil ? "Start workout" : "Resume \(unfinished?.workoutName ?? "")")
                        .font(.headline).foregroundStyle(Color.night)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(unfinished == nil ? "startWorkoutButton" : "resumeWorkout")
            }
            .padding(18)
            .background(LinearGradient.night, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LinearGradient.brand.opacity(0.6), lineWidth: 1))
        } else {
            Text("Program complete. Choose your next one in Settings.").card()
        }
    }

    private func start(plan: TrainingPlan, program: Program, week: ProgramWeek, workout: ProgramWorkout, version: SessionVersion) {
        guard let content = store.content else { return }
        let built = WorkoutPlanner.plan(program: program, workout: workout, version: version, content: content,
                                        equipment: Set(plan.equipment), chosenSwaps: [:])
        let log = WorkoutLog(programId: program.id, weekNumber: week.number, workoutPosition: workout.position,
                             workoutName: workout.name, version: version, swaps: built.swaps)
        context.insert(log)
        try? context.save()
        activeLog = log
    }

    private var greeting: String {
        let name = profiles.first?.name ?? ""
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? part : "\(part), \(name)"
    }
}

/// This week, Monday to Sunday: trained days filled, planned days ringed, fixed activities dotted.
struct WeekStrip: View {
    let logs: [WorkoutLog]
    let plan: TrainingPlan

    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let trained = Set(logs.filter { $0.finishedAt != nil }.map { cal.startOfDay(for: $0.startedAt) })
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let weekday = Calendar.current.component(.weekday, from: day)
                let isToday = cal.isDateInToday(day)
                let done = trained.contains(cal.startOfDay(for: day))
                let planned = plan.preferredWeekdays.contains(weekday)
                let fixed = plan.fixedCommitments.contains { $0.weekday == weekday }
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.gold : Color.inkMuted)
                    ZStack {
                        if done {
                            Circle().fill(LinearGradient.brand)
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.night)
                        } else {
                            Circle().stroke(planned ? Color.gold.opacity(0.7) : Color.hairline,
                                            style: StrokeStyle(lineWidth: 1.5, dash: planned ? [] : [3, 3]))
                            Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(isToday ? Color.ink : Color.inkMuted)
                        }
                    }
                    .frame(width: 34, height: 34)
                    Circle().fill(fixed ? Color.emerald : Color.clear).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(done ? "trained" : planned ? "training day" : "rest")\(fixed ? ", fixed activity" : "")")
            }
        }
        .card()
    }
}

struct FoodCard: View {
    let plan: NutritionPlan
    var totals: Macros = Macros()
    private var eaten: Int { Int(totals.kcal.rounded()) }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.hairline, lineWidth: 10)
                Circle().trim(from: 0, to: min(1, CGFloat(eaten) / CGFloat(max(plan.calories, 1))))
                    .stroke(LinearGradient.brand, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(abs(plan.calories - eaten))").font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
                    Text(eaten > plan.calories ? "kcal over" : "kcal left").font(.caption2).foregroundStyle(Color.inkMuted)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 10) {
                Text("FOOD TODAY").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                MacroBar(label: "Protein", value: Int(totals.protein.rounded()), target: plan.protein)
                MacroBar(label: "Carbs", value: Int(totals.carbs.rounded()), target: plan.carbs)
                MacroBar(label: "Fat", value: Int(totals.fat.rounded()), target: plan.fat)
                if plan.startAtMaintenance {
                    Text("Maintenance for your first two weeks").font(.caption2).foregroundStyle(Color.inkMuted)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct MacroBar: View {
    let label: String
    let value: Int
    let target: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.ink)
                Spacer()
                Text("\(value) / \(target) g").font(.caption.monospacedDigit()).foregroundStyle(Color.inkMuted)
            }
            BrandProgress(value: Double(value) / Double(max(target, 1)))
        }
    }
}

struct CheckInCard: View {
    let settings: CheckInSettings
    var body: some View {
        let days = daysUntil(settings.weekday)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEEKLY CHECK-IN").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(weekdayNames[settings.weekday - 1]), in \(days) days")
                    .font(.title3.weight(.semibold)).foregroundStyle(Color.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label(String(format: "%g h sleep", settings.sleepGoalHours), systemImage: "moon.stars")
                Label("\(settings.stepsGoal.formatted()) steps", systemImage: "figure.walk")
            }
            .font(.caption).foregroundStyle(Color.inkMuted)
        }
        .card()
    }

    private func daysUntil(_ weekday: Int) -> Int {
        let today = Calendar.current.component(.weekday, from: .now)
        return (weekday - today + 7) % 7
    }
}

extension Program {
    /// The session at a rotation index (0 = week 1, session 1), or nil when finished.
    func session(at index: Int) -> (week: ProgramWeek, workout: ProgramWorkout)? {
        var i = index
        for week in weeks {
            if i < week.workouts.count { return (week, week.workouts[i]) }
            i -= week.workouts.count
        }
        return nil
    }
}

// MARK: - Train

struct TrainView: View {
    @Environment(ContentStore.self) private var store
    @Query private var plans: [TrainingPlan]

    var body: some View {
        NavigationStack {
            if let plan = plans.first, let program = store.content?.program(plan.programId) {
                List {
                    Section {
                        LabeledContent("Program", value: program.name)
                        LabeledContent("Sessions a week", value: program.sessionsPerWeekText)
                        LabeledContent("Typical session", value: "about \(program.averageSessionMinutes) min")
                    } footer: {
                        Text("Workout logging, progression and swaps during a session arrive in the next update. You can preview every session now.")
                    }
                    ForEach(program.weeks) { week in
                        Section {
                            ForEach(week.workouts) { workout in
                                NavigationLink {
                                    WorkoutPreview(program: program, week: week, workout: workout)
                                } label: {
                                    LabeledContent(workout.name, value: "\(workout.estimatedMinutes) min")
                                }
                            }
                        } header: {
                            Text(weekHeader(week))
                        }
                    }
                }
                .themedList()
                .navigationTitle("Train")
            } else {
                ContentUnavailableView("No program yet", systemImage: "dumbbell")
                    .navigationTitle("Train")
            }
        }
    }

    private func weekHeader(_ w: ProgramWeek) -> String {
        var s = "Week \(w.number)"
        if let phase = w.phase { s += " · \(phase)" } else if w.isDeload == true { s += " · Easier week" }
        return s
    }
}

struct WorkoutPreview: View {
    let program: Program
    let week: ProgramWeek
    let workout: ProgramWorkout
    @State private var selected: ExerciseSlot?

    var body: some View {
        List {
            Section {
                Text("About \(workout.estimatedMinutes) min including a 7 minute warm-up and 5 minute cool-down.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(workout.slots) { slot in
                Button { selected = slot } label: { SlotRow(slot: slot) }
                    .accessibilityHint("Shows form cues and swaps")
            }
        }
        .themedList()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { slot in
            ExerciseSheet(exerciseId: slot.exerciseId, slot: slot, maxDifficulty: program.maxSwapDifficulty ?? 3)
        }
    }
}

struct SlotRow: View {
    let slot: ExerciseSlot
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let ss = slot.superset {
                Text(ss.label ?? ss.group)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Superset \(ss.label ?? ss.group)")
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(slot.exercise.capitalized).foregroundStyle(.primary)
                    if slot.isMainLift == true {
                        Text("Main").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text(prescription).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var prescription: String {
        var parts: [String] = []
        let sets = slot.sets.count ?? 0
        parts.append("\(sets) × \(slot.reps.display)")
        if let e = slot.effort { parts.append(e.display) }
        if let p = slot.pct1RM, let lo = p.min, let hi = p.max {
            parts.append(lo == hi ? "\(Int(lo * 100))% 1RM" : "\(Int(lo * 100))-\(Int(hi * 100))% 1RM")
        }
        if let r = slot.rest, !(r.display.isEmpty) { parts.append("rest \(r.display.lowercased())") }
        return parts.joined(separator: " · ")
    }
}
