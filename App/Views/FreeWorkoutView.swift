import SwiftUI
import SwiftData
import SteadyCore

/// An open workout: no program, you choose the exercises as you go. Your logged sets still feed
/// progression suggestions, records, and weekly volume. It does not move your program on.
enum FreeWorkout {
    static func start(in context: ModelContext) -> WorkoutLog {
        let log = WorkoutLog(programId: "open", weekNumber: 0, workoutPosition: 0, workoutName: "Open workout",
                             version: .standard, swaps: [:])
        log.isFreestyle = true
        context.insert(log)
        try? context.save()
        return log
    }

    /// Removes an exercise that has no sets yet, and closes the gap in the sets recorded for the ones after it.
    static func remove(at index: Int, from log: WorkoutLog) {
        guard log.freeExerciseIds.indices.contains(index),
              !log.sets.contains(where: { $0.slotOrder == index }) else { return }
        log.freeExerciseIds.remove(at: index)
        for s in log.sets where s.slotOrder > index { s.slotOrder -= 1 }
    }
}

struct FreeWorkoutView: View {
    @Bindable var log: WorkoutLog
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @Query private var logs: [WorkoutLog]
    @State private var restEndsAt: Date?
    @State private var restTotal = 90
    @State private var infoFor: String?
    @State private var picking = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    private func planned(_ id: String, order: Int, content: BundledContent) -> PlannedExercise {
        let ex = content.library[id]
        let done = log.sets.filter { $0.slotOrder == order }.count
        return PlannedExercise(moduleExerciseId: id, name: ex?.name ?? "Exercise", id: order, sets: max(3, done + 1),
                               repMin: 8, repMax: 12, restSeconds: 90, perSide: ex?.unilateral ?? false)
    }

    var body: some View {
        if let content = store.content {
            let items = log.freeExerciseIds.enumerated().map { planned($1, order: $0, content: content) }
            ScrollView {
                VStack(spacing: 16) {
                    WorkoutHeader(name: log.workoutName, version: .standard, week: 0, done: log.sets.count,
                                  total: max(items.reduce(0) { $0 + $1.sets }, log.sets.count), started: log.startedAt,
                                  eyebrow: "NO PROGRAM · YOUR CHOICE")
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "dumbbell").font(.largeTitle).foregroundStyle(Color.gold)
                            Text("Add your first exercise").font(.headline)
                            Text("Choose from the exercise list or create your own. Your sets count towards your records and weekly volume.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(24).card()
                    }
                    ForEach(items) { item in
                        let ex = content.library[item.exerciseId]
                        let plan = plans.first
                        VStack(spacing: 6) {
                            ExerciseCard(item: item, log: log, exercise: ex,
                                         suggestion: Progression.suggest(for: item, exercise: ex,
                                                                         history: WorkoutPlanner.history(item.exerciseId, logs: logs.filter { $0 !== log }),
                                                                         oneRepMaxes: plan?.oneRepMaxes ?? [:],
                                                                         increment: plan?.upperIncrement ?? 2.5),
                                         isSwapped: false, canSwap: false, focused: $focused,
                                         onSetDone: { setDone(item) }, onSwap: {}, onInfo: { infoFor = item.exerciseId })
                            if !log.sets.contains(where: { $0.slotOrder == item.id }) {
                                Button("Remove \(item.name)", role: .destructive) {
                                    FreeWorkout.remove(at: item.id, from: log)
                                    try? context.save()
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    Button { picking = true } label: {
                        Label("Add exercise", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addExercise")
                    VStack(spacing: 10) {
                        Button { if log.sets.isEmpty { confirmDiscard = true } else { confirmFinish = true } } label: {
                            Text("Finish workout").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("finishWorkout")
                        Button("Discard workout", role: .destructive) { confirmDiscard = true }.font(.subheadline)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.night.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let end = restEndsAt {
                    RestTimerBar(endsAt: end, total: restTotal,
                                 onAdd: { restEndsAt = (restEndsAt ?? .now).addingTimeInterval(30); restTotal += 30 },
                                 onLess: { restEndsAt = (restEndsAt ?? .now).addingTimeInterval(-15); restTotal = max(15, restTotal - 15) },
                                 onDone: { restEndsAt = nil })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: restEndsAt)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePicker { id in
                    log.freeExerciseIds.append(id)
                    try? context.save()
                }
            }
            .sheet(item: Binding(get: { infoFor.map { InfoID(id: $0) } }, set: { infoFor = $0?.id })) { info in
                ExerciseSheet(exerciseId: info.id)
            }
            .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish") {
                    log.finishedAt = .now
                    try? context.save()
                    dismiss()
                }
            } message: { Text("It is saved to your history. Your program stays where it was.") }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    context.delete(log)
                    try? context.save()
                    dismiss()
                }
            } message: { Text("Nothing from this session is kept.") }
        }
    }

    private struct InfoID: Identifiable { let id: String }

    private func setDone(_ item: PlannedExercise) {
        focused = false
        restTotal = item.restSeconds
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(item.restSeconds))
    }
}
