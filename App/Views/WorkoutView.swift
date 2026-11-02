import SwiftUI
import SwiftData
import SteadyCore

// MARK: - Building today's session

enum WorkoutPlanner {
    /// Today's exercises: the version applied, then swaps for missing equipment
    /// (automatic) and any the user chose (stored on the log).
    static func plan(program: Program, workout: ProgramWorkout, version: SessionVersion, content: BundledContent,
                     equipment: Set<String>, chosenSwaps: [Int: String]) -> (plan: [PlannedExercise], swaps: [Int: String]) {
        var plan = SessionBuilder.build(workout, version: version, library: content.library)
        var swaps = chosenSwaps
        for i in plan.indices {
            let slot = workout.slots.first { $0.order == plan[i].id }
            if let chosen = chosenSwaps[plan[i].id] {
                apply(&plan[i], chosen, content)
                continue
            }
            let pick = Substitution.choose(plan[i].exerciseId, library: content.library, available: equipment,
                                           maxDifficulty: program.maxSwapDifficulty ?? 3,
                                           slotAlternatives: slot?.alternativeIds ?? [])
            if let id = pick.id, id != plan[i].exerciseId {
                apply(&plan[i], id, content)
                swaps[plan[i].id] = id
            }
        }
        return (plan, swaps)
    }

    static func apply(_ e: inout PlannedExercise, _ newId: String, _ content: BundledContent) {
        guard let ex = content.library[newId] else { return }
        let old = content.library[e.exerciseId]
        e.exerciseId = newId
        e.name = ex.name
        if ex.unilateral && !(old?.unilateral ?? false) { e.perSide = true; e.repsText = e.repsText.hasSuffix("each side") ? e.repsText : e.repsText + " each side" }
    }

    /// Past finished sessions of one exercise, oldest first, for progression.
    static func history(_ exerciseId: String, logs: [WorkoutLog]) -> [ExerciseHistory] {
        logs.filter { $0.finishedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { log in
                let sets = log.sets.filter { $0.exerciseId == exerciseId }.sorted { $0.setIndex < $1.setIndex }
                guard let first = sets.first else { return nil }
                return ExerciseHistory(date: log.startedAt,
                                       sets: sets.map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) },
                                       targetSets: first.targetSets, targetTop: sets.map(\.targetReps),
                                       targetMin: sets.map(\.minReps), maxRPE: first.maxRPE)
            }
    }
}

// MARK: - Start sheet

struct StartWorkoutSheet: View {
    let program: Program
    let week: ProgramWeek
    let workout: ProgramWorkout
    let onStart: (SessionVersion) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var version: SessionVersion = .standard

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SessionVersion.allCases) { v in
                        Button { version = v } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.label).foregroundStyle(.primary)
                                    Text("\(v.detail) About \(minutes(v)) min.").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if version == v { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityAddTraits(version == v ? .isSelected : [])
                        .accessibilityIdentifier("version-\(v.rawValue)")
                    }
                } header: { Text("How much today?") } footer: {
                    Text("Short on time or energy? A shorter version keeps your progress going; the program itself doesn't change.")
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onStart(version); dismiss() }.accessibilityIdentifier("startWorkout")
                }
            }
        }
    }

    private func minutes(_ v: SessionVersion) -> Int {
        guard let c = store.content else { return workout.estimatedMinutes }
        return SessionBuilder.estimatedMinutes(SessionBuilder.build(workout, version: v, library: c.library), version: v)
    }
}

// MARK: - Active workout

struct ActiveWorkoutView: View {
    @Bindable var log: WorkoutLog
    let program: Program
    let workout: ProgramWorkout
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @Query private var logs: [WorkoutLog]
    @State private var restEndsAt: Date?
    @State private var swapFor: PlannedExercise?
    @State private var infoFor: PlannedExercise?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

    var body: some View {
        if let content = store.content, let trainingPlan = plans.first {
            let built = WorkoutPlanner.plan(program: program, workout: workout, version: log.version, content: content,
                                            equipment: Set(trainingPlan.equipment), chosenSwaps: log.swaps)
            List {
                ForEach(Array(built.plan.enumerated()), id: \.element.id) { index, item in
                    ExerciseCard(item: item, log: log, content: content,
                                 suggestion: Progression.suggest(for: item, exercise: content.library[item.exerciseId],
                                                                 history: WorkoutPlanner.history(item.exerciseId, logs: logs.filter { $0 !== log }),
                                                                 oneRepMaxes: trainingPlan.oneRepMaxes),
                                 isSwapped: item.exerciseId != item.originalExerciseId,
                                 onSetDone: { setDone(item, index: index, plan: built.plan) },
                                 onSwap: { swapFor = item },
                                 onInfo: { infoFor = item })
                }
                Section {
                    Button("Finish workout") { confirmFinish = true }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("finishWorkout")
                    Button("Discard workout", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let end = restEndsAt { RestTimerBar(endsAt: end) { restEndsAt = nil } }
            }
            .navigationTitle(log.workoutName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
            }
            .sheet(item: $swapFor) { item in
                SwapSheet(item: item, content: content, equipment: Set(trainingPlan.equipment),
                          maxDifficulty: program.maxSwapDifficulty ?? 3) { newId in
                    log.swaps[item.id] = newId
                    try? context.save()
                }
            }
            .sheet(item: $infoFor) { item in
                ExerciseSheet(exerciseId: item.exerciseId, slot: workout.slots.first { $0.order == item.id },
                              maxDifficulty: program.maxSwapDifficulty ?? 3)
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish") {
                    log.finishedAt = .now
                    trainingPlan.nextSessionIndex += 1
                    try? context.save()
                    dismiss()
                }
            } message: { Text("Sets you didn't tick count as not done, and your next session moves on.") }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    context.delete(log)
                    try? context.save()
                    dismiss()
                }
            } message: { Text("Nothing from this session is kept, and it stays as your next session.") }
        }
    }

    /// Rest after a set: none between superset partners, the round's rest after the last one.
    private func setDone(_ item: PlannedExercise, index: Int, plan: [PlannedExercise]) {
        if let g = item.supersetGroup, index + 1 < plan.count, plan[index + 1].supersetGroup == g {
            restEndsAt = nil
            return
        }
        let rest = item.restSeconds > 0 ? item.restSeconds : 60
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(rest))
    }
}

struct ExerciseCard: View {
    let item: PlannedExercise
    @Bindable var log: WorkoutLog
    let content: BundledContent
    let suggestion: LoadSuggestion
    let isSwapped: Bool
    let onSetDone: () -> Void
    let onSwap: () -> Void
    let onInfo: () -> Void
    @Environment(\.modelContext) private var context

    private var done: [SetLog] {
        log.sets.filter { $0.slotOrder == item.id }.sorted { $0.setIndex < $1.setIndex }
    }

    var body: some View {
        Section {
            if let note = suggestionLine { Text(note).font(.footnote).foregroundStyle(.secondary) }
            ForEach(0..<item.sets, id: \.self) { i in
                SetRow(index: i, item: item, logged: done.first { $0.setIndex == i },
                       startWeight: done.last?.weight ?? suggestion.weight ?? 0) { weight, reps in
                    let set = SetLog(exerciseId: item.exerciseId, slotOrder: item.id, setIndex: i, weight: weight,
                                     reps: reps, rpe: nil, targetSets: item.sets, targetReps: item.targetReps(set: i),
                                     minReps: item.minimumReps(set: i),
                                     maxRPE: item.effortType == .rpe ? item.effortMax : nil)
                    context.insert(set)
                    set.workout = log
                    try? context.save()
                    onSetDone()
                } onUndo: { set in
                    context.delete(set)
                    try? context.save()
                }
            }
        } header: {
            HStack {
                if let g = item.supersetGroup {
                    Text(g).font(.caption.bold()).padding(.horizontal, 6).background(.tint.opacity(0.15), in: Capsule())
                        .accessibilityLabel("Superset \(g)")
                }
                Button(action: onInfo) { Text(item.name).font(.headline).foregroundStyle(.primary) }
                    .accessibilityHint("Form cues and demo video")
                Spacer()
                Button(action: onSwap) { Image(systemName: "arrow.triangle.swap") }
                    .accessibilityLabel("Swap \(item.name)")
            }
            .textCase(nil)
        } footer: {
            Text(prescription)
        }
    }

    private var prescription: String {
        var parts = ["\(item.sets) × \(item.repsText)"]
        if let e = item.effortText { parts.append(e) }
        if item.restSeconds > 0 { parts.append("rest \(item.restSeconds / 60 > 0 ? "\(item.restSeconds / 60) min" : "\(item.restSeconds) s")") }
        if isSwapped { parts.append("swapped from the program") }
        return parts.joined(separator: " · ")
    }

    private var suggestionLine: String? {
        switch suggestion.kind {
        case .byFeel: return suggestion.reason
        default:
            guard let w = suggestion.weight else { return suggestion.reason }
            return "Suggested \(NumberText.format(w)) kg. \(suggestion.reason)"
        }
    }
}

struct SetRow: View {
    let index: Int
    let item: PlannedExercise
    let logged: SetLog?
    let startWeight: Double
    let onDone: (Double, Int) -> Void
    let onUndo: (SetLog) -> Void
    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var ready = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)").font(.headline).frame(width: 22).foregroundStyle(.secondary)
            if let logged {
                Text("\(NumberText.format(logged.weight)) kg × \(logged.reps)").frame(maxWidth: .infinity, alignment: .leading)
                Button { onUndo(logged) } label: {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                }
                .accessibilityLabel("Set \(index + 1) done. Tap to undo")
            } else {
                Stepper(value: $weight, in: 0...500, step: 2.5) {
                    Text("\(NumberText.format(weight)) kg").monospacedDigit()
                }
                .accessibilityLabel("Weight for set \(index + 1)")
                Stepper(value: $reps, in: 0...100) { Text("× \(reps)").monospacedDigit() }
                    .accessibilityLabel("Reps for set \(index + 1)")
                Button { onDone(weight, reps) } label: {
                    Image(systemName: "circle").font(.title2)
                }
                .accessibilityLabel("Mark set \(index + 1) done")
                .accessibilityIdentifier("setDone-\(item.id)-\(index)")
            }
        }
        .buttonStyle(.borderless)
        .onAppear {
            if !ready { weight = startWeight; reps = item.targetReps(set: index) ?? 10; ready = true }
        }
        .onChange(of: startWeight) { _, w in if logged == nil { weight = w } }
    }
}

struct RestTimerBar: View {
    let endsAt: Date
    let onDone: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(endsAt.timeIntervalSince(ctx.date).rounded(.up)))
            HStack {
                Image(systemName: "timer")
                Text(left > 0 ? "Rest \(left / 60):\(String(format: "%02d", left % 60))" : "Rest done. Next set")
                    .monospacedDigit().font(.headline)
                Spacer()
                Button(left > 0 ? "Skip" : "OK", action: onDone)
            }
            .padding()
            .background(.thinMaterial)
            .accessibilityElement(children: .combine)
        }
    }
}

struct SwapSheet: View {
    let item: PlannedExercise
    let content: BundledContent
    let equipment: Set<String>
    let maxDifficulty: Int
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if item.exerciseId != item.originalExerciseId, let orig = content.library[item.originalExerciseId] {
                        Button("Back to \(orig.name)") { onPick(orig.id); dismiss() }
                    }
                    ForEach(Substitution.options(item.originalExerciseId, library: content.library, available: equipment,
                                                 maxDifficulty: maxDifficulty, limit: 8)) { ex in
                        Button { onPick(ex.id); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).foregroundStyle(.primary)
                                Text(ex.cues).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                } footer: {
                    Text("For this session only. Each exercise keeps its own weight history; a swap starts by feel at the same effort.")
                }
            }
            .navigationTitle("Swap \(item.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
