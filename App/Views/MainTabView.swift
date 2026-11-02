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
            ComingSoonView(title: "Food", systemImage: "fork.knife",
                           detail: "Barcode scanning, your food log and adaptive targets arrive in the nutrition update.")
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
    @Query private var profiles: [UserProfile]
    @Query private var plans: [TrainingPlan]
    @Query private var food: [NutritionPlan]
    @Query private var checkIns: [CheckInSettings]
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt == nil }, sort: \WorkoutLog.startedAt, order: .reverse)
    private var unfinished: [WorkoutLog]
    @Environment(\.modelContext) private var context
    @State private var startSheet = false
    @State private var activeLog: WorkoutLog?

    var body: some View {
        NavigationStack {
            List {
                if let plan = plans.first, let program = store.content?.program(plan.programId) {
                    let next = program.session(at: plan.nextSessionIndex)
                    Section("Next session") {
                        if let next {
                            NavigationLink {
                                WorkoutPreview(program: program, week: next.week, workout: next.workout)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(next.workout.name).font(.headline)
                                    Text("Week \(next.week.number) of \(program.weeks.count) · about \(next.workout.estimatedMinutes) min · \(next.workout.slots.count) exercises")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("nextSession")
                            if let open = unfinished.first {
                                Button("Resume \(open.workoutName)") { activeLog = open }
                                    .accessibilityIdentifier("resumeWorkout")
                            } else {
                                Button("Start workout") { startSheet = true }
                                    .accessibilityIdentifier("startWorkoutButton")
                            }
                        } else {
                            Text("Program complete. Choose your next one in Settings.")
                        }
                    }
                }
                if let n = food.first {
                    Section("Food today") {
                        LabeledContent("Calories", value: "\(n.calories) kcal")
                        LabeledContent("Protein", value: "\(n.protein) g")
                        if n.startAtMaintenance {
                            Text("Eating at maintenance for your first two weeks.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let c = checkIns.first {
                    Section("This week") {
                        LabeledContent("Check-in day", value: weekdayNames[c.weekday - 1])
                        LabeledContent("Sleep goal", value: String(format: "%g h", c.sleepGoalHours))
                        LabeledContent("Steps goal", value: c.stepsGoal.formatted())
                    }
                }
            }
            .navigationTitle(greeting)
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
