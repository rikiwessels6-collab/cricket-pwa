import SwiftUI
import SwiftData
import SteadyCore

// MARK: - Building today's session

enum WorkoutPlanner {
    /// Programs for beginners: weeks 1-4 are an easy on-ramp (2 sets, about 3-4 reps in reserve).
    static let onRampPrograms: Set<String> = ["ss-strength-foundations", "ss-strong-for-life"]

    /// A suggested weight scaled by the session's load factor, kept to 0.5 kg steps.
    static func scaled(_ w: Double, factor: Double) -> Double {
        factor == 1 ? w : max(0, (w * factor * 2).rounded(.down) / 2)
    }

    /// Today's exercises: the version applied, then swaps for missing equipment
    /// (automatic) and any the user chose (stored on the log).
    static func plan(program: Program, workout: ProgramWorkout, version: SessionVersion, content: BundledContent,
                     equipment: Set<String>, chosenSwaps: [Int: String], week: Int = 99) -> (plan: [PlannedExercise], swaps: [Int: String]) {
        var plan = SessionBuilder.build(workout, version: version, library: content.library)
        if onRampPrograms.contains(program.id) { plan = SessionBuilder.applyOnRamp(plan, week: week) }
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

    /// Where an empty field starts the first time: the bar, light dumbbells, or a light pin.
    static func defaultStartWeight(_ ex: Exercise?) -> Double {
        guard let e = ex, e.loadable else { return 0 }
        let kit = Set(e.equipment.flatMap { $0.split(separator: "/").map(String.init) })
        if kit.contains("barbell") || kit.contains("trap_bar") { return 20 }
        if kit.contains("ez_bar") { return 10 }
        if kit.contains("dumbbells") || kit.contains("kettlebell") { return e.unilateral ? 6 : 8 }
        return 10
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
    let onStart: (SessionVersion, Readiness.Choice, ReasonCode?) -> Void
    @Environment(ContentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var version: SessionVersion = .standard
    @State private var answers = ReadinessAnswers()
    @State private var checkOpen = false
    @State private var choice: Readiness.Choice = .asPlanned
    @State private var easeBack = true
    @Query(filter: #Predicate<WorkoutLog> { $0.finishedAt != nil }, sort: \WorkoutLog.startedAt, order: .reverse) private var finished: [WorkoutLog]

    private var advice: Readiness.Advice { Readiness.advise(answers) }
    private var effectiveVersion: SessionVersion { choice == .fewerSets ? .lowEnergy : version }

    var body: some View {
        NavigationStack {
            Form {
                returnSection
                readinessSection
                if let note = week.phaseNote, week.lowFatigueOptional != true {
                    Section("Week \(week.number) · \(week.phase ?? "")") { Text(note).font(.footnote) }
                }
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
                    if week.lowFatigueOptional == true {
                        Text("\(week.phase ?? "Lower-fatigue week"): \(week.phaseNote ?? "Low energy is a good choice if you're feeling run down.")")
                    } else {
                        Text("Short on time or energy? A shorter version keeps your progress going; the program itself doesn't change.")
                    }
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let easing = returnAdvice != nil && easeBack && choice == .asPlanned
                        onStart(effectiveVersion, easing ? .lowerLoad : choice, easing ? ReasonCode.missedReturnReduction : (checkOpen ? advice.code : nil))
                        dismiss()
                    }.accessibilityIdentifier("startWorkout")
                }
            }
        }
    }

    private var returnAdvice: ReturnAdvice? { ReturnToTraining.advice(lastSession: finished.first?.finishedAt) }

    @ViewBuilder private var returnSection: some View {
        if let advice = returnAdvice {
            Section {
                Toggle(isOn: $easeBack) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ease back in")
                        Text(advice.message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("easeBack")
            }
        }
    }

    @ViewBuilder private var readinessSection: some View {
        Section {
            DisclosureGroup("How are you today? (optional)", isExpanded: $checkOpen) {
                Picker("Sleep", selection: $answers.sleep) {
                    ForEach(ReadinessAnswers.Level.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Energy", selection: $answers.energy) {
                    ForEach(ReadinessAnswers.Level.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Anything bothering you?", selection: $answers.concern) {
                    ForEach(ReadinessAnswers.Concern.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Note (stays on this phone)", text: $answers.note)
                if let stop = advice.stopMessage {
                    Label(stop, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.gold).font(.callout)
                }
                ForEach(Readiness.Choice.allCases) { c in
                    Button { choice = c } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.label + (c == advice.suggested ? " (suggested)" : "")).foregroundStyle(.primary)
                                Text(c.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if choice == c { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityAddTraits(choice == c ? .isSelected : [])
                }
            }
            .onChange(of: answers) { _, _ in choice = advice.suggested }
        } footer: {
            Text("These are suggestions, not medical advice. You decide.")
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
    @State private var restTotal: Int = 90
    @State private var swapFor: PlannedExercise?
    @State private var infoFor: PlannedExercise?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @FocusState private var focused: Bool

    var body: some View {
        if let content = store.content, let trainingPlan = plans.first {
            let built = WorkoutPlanner.plan(program: program, workout: workout, version: log.version, content: content,
                                            equipment: Set(trainingPlan.equipment), chosenSwaps: log.swaps, week: log.weekNumber)
            let totalSets = built.plan.reduce(0) { $0 + $1.sets }
            ScrollView {
                VStack(spacing: 16) {
                    WorkoutHeader(name: log.workoutName, version: log.version, week: log.weekNumber,
                                  done: log.sets.count, total: totalSets, started: log.startedAt)
                    ForEach(Array(built.plan.enumerated()), id: \.element.id) { index, item in
                        let ex = content.library[item.exerciseId]
                        ExerciseCard(item: item, log: log, exercise: ex,
                                     suggestion: Progression.suggest(for: item, exercise: ex,
                                                                     history: WorkoutPlanner.history(item.exerciseId, logs: logs.filter { $0 !== log }),
                                                                     oneRepMaxes: trainingPlan.oneRepMaxes,
                                                                     increment: (ex?.pattern.hasPrefix("squat") == true || ex?.pattern.hasPrefix("hinge") == true) && ex?.tier == "main"
                                                                         ? trainingPlan.lowerIncrement : trainingPlan.upperIncrement),
                                     isSwapped: item.exerciseId != item.originalExerciseId,
                                     focused: $focused,
                                     onSetDone: { setDone(item, index: index, plan: built.plan) },
                                     onSwap: { swapFor = item },
                                     onInfo: { infoFor = item })
                    }
                    VStack(spacing: 10) {
                        Button { confirmFinish = true } label: {
                            Text("Finish workout").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("finishWorkout")
                        Button("Discard workout", role: .destructive) { confirmDiscard = true }
                            .font(.subheadline)
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
        focused = false
        if let g = item.supersetGroup, index + 1 < plan.count, plan[index + 1].supersetGroup == g {
            restEndsAt = nil
            return
        }
        let rest = item.restSeconds > 0 ? item.restSeconds : 60
        restTotal = rest
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(rest))
    }
}

struct WorkoutHeader: View {
    let name: String
    let version: SessionVersion
    let week: Int
    let done: Int
    let total: Int
    let started: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK \(week)\(version == .standard ? "" : " · \(version.label.uppercased())")")
                        .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.gold)
                    Text(name).font(.largeTitle.weight(.bold))
                }
                Spacer()
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    Text(Duration.seconds(ctx.date.timeIntervalSince(started)), format: .time(pattern: .minuteSecond))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed time")
                }
            }
            HStack(spacing: 12) {
                BrandProgress(value: Double(done) / Double(max(total, 1)))
                Text("\(done)/\(total) sets").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseCard: View {
    let item: PlannedExercise
    @Bindable var log: WorkoutLog
    let exercise: Exercise?
    let suggestion: LoadSuggestion
    let isSwapped: Bool
    var focused: FocusState<Bool>.Binding
    let onSetDone: () -> Void
    let onSwap: () -> Void
    let onInfo: () -> Void
    @Environment(\.modelContext) private var context

    private var done: [SetLog] {
        log.sets.filter { $0.slotOrder == item.id }.sorted { $0.setIndex < $1.setIndex }
    }
    private var loadable: Bool { exercise?.loadable ?? true }
    private var accepted: Bool { log.acceptedSuggestions.contains(item.exerciseId) }
    private var declined: Bool { log.declinedSuggestions.contains(item.exerciseId) }
    /// Increases and deloads are only applied once you accept them.
    private var pendingConfirmation: Bool { suggestion.needsConfirmation && !accepted && !declined && done.isEmpty }
    private var suggestedWeight: Double? {
        guard let w = suggestion.weight else { return nil }
        if suggestion.needsConfirmation && !accepted {
            return WorkoutPlanner.scaled(suggestion.previousWeight ?? w, factor: log.loadFactor)
        }
        return WorkoutPlanner.scaled(w, factor: log.loadFactor)
    }
    private var startWeight: Double {
        done.last?.weight ?? suggestedWeight ?? WorkoutPlanner.defaultStartWeight(exercise)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let g = item.supersetGroup { Chip(text: "SUPERSET \(g)", prominent: true) }
                        if item.isMainLift { Chip(text: "MAIN LIFT", prominent: false) }
                        if isSwapped { Chip(text: "SWAPPED", prominent: false) }
                    }
                    Button(action: onInfo) {
                        HStack(spacing: 6) {
                            Text(item.name).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Form cues and demo video")
                    Text(prescription).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onSwap) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Color.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap \(item.name)")
            }
            if let line = suggestionLine {
                Label(line, systemImage: suggestionIcon)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if pendingConfirmation {
                    HStack(spacing: 10) {
                        Button("Use \(NumberText.format(WorkoutPlanner.scaled(suggestion.weight ?? 0, factor: log.loadFactor))) kg") {
                            log.acceptedSuggestions.append(item.exerciseId); try? context.save()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("acceptSuggestion")
                        Button("Keep \(NumberText.format(WorkoutPlanner.scaled(suggestion.previousWeight ?? 0, factor: log.loadFactor))) kg") {
                            log.declinedSuggestions.append(item.exerciseId); try? context.save()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("declineSuggestion")
                    }
                    .font(.subheadline)
                }
            }
            VStack(spacing: 8) {
                HStack {
                    Text("SET").frame(width: 34, alignment: .leading)
                    Text(loadable ? "KG" : "LOAD").frame(maxWidth: .infinity)
                    Text("REPS").frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44)
                }
                .font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(Color.inkMuted.opacity(0.7))
                ForEach(0..<item.sets, id: \.self) { i in
                    SetRow(index: i, item: item, logged: done.first { $0.setIndex == i },
                           startWeight: startWeight, loadable: loadable, focused: focused) { weight, reps in
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
            }
        }
        .card()
    }

    private var prescription: String {
        var parts = ["\(item.sets) × \(item.repsText)"]
        if let e = item.effortText { parts.append(e) }
        if item.restSeconds > 0 {
            parts.append(item.restSeconds >= 60 ? "\(NumberText.format(Double(item.restSeconds) / 60)) min rest" : "\(item.restSeconds) s rest")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var suggestionIcon: String {
        switch suggestion.kind {
        case .increase: return "arrow.up.circle.fill"
        case .deload: return "arrow.down.circle"
        case .percent: return "percent"
        case .byFeel: return "hand.raised"
        default: return "equal.circle"
        }
    }

    private var suggestionLine: String? {
        guard loadable else { return nil }
        switch suggestion.kind {
        case .byFeel: return suggestion.reason
        default:
            guard let w = suggestion.weight else { return suggestion.reason }
            if declined { return "Keeping \(NumberText.format(suggestedWeight ?? w)) kg for today." }
            return "\(NumberText.format(WorkoutPlanner.scaled(w, factor: log.loadFactor))) kg. \(suggestion.reason)"
        }
    }
}

struct Chip: View {
    let text: String
    let prominent: Bool
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).tracking(0.8)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(prominent ? Color.night : Color.gold)
            .background(prominent ? Color.gold : Color.gold.opacity(0.14), in: Capsule())
    }
}

struct SetRow: View {
    let index: Int
    let item: PlannedExercise
    let logged: SetLog?
    let startWeight: Double
    let loadable: Bool
    var focused: FocusState<Bool>.Binding
    let onDone: (Double, Int) -> Void
    let onUndo: (SetLog) -> Void
    @State private var weight: Double?
    @State private var reps: Int?
    @State private var ready = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(logged == nil ? Color.inkMuted : Color.gold)
                .frame(width: 34, alignment: .leading)
            if let logged {
                ValuePill(text: loadable ? NumberText.format(logged.weight) : "BW", done: true)
                ValuePill(text: "\(logged.reps)", done: true)
                Button { onUndo(logged) } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold)).foregroundStyle(Color.night)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Set \(index + 1) done, \(NumberText.format(logged.weight)) kilograms, \(logged.reps) reps. Tap to undo")
            } else {
                if loadable {
                    TextField("0", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .focused(focused)
                        .modifier(PillField())
                        .accessibilityLabel("Weight for set \(index + 1), kilograms")
                } else {
                    ValuePill(text: "BW", done: false)
                }
                TextField("0", value: $reps, format: .number)
                    .keyboardType(.numberPad)
                    .focused(focused)
                    .modifier(PillField())
                    .accessibilityLabel("Reps for set \(index + 1)")
                Button { onDone(weight ?? 0, reps ?? 0) } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold)).foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Mark set \(index + 1) done")
                .accessibilityIdentifier("setDone-\(item.id)-\(index)")
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: logged != nil)
        .onAppear {
            if !ready { weight = startWeight; reps = item.targetReps(set: index) ?? 10; ready = true }
        }
        .onChange(of: startWeight) { _, w in if logged == nil { weight = w } }
    }
}

struct PillField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color.ink)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ValuePill: View {
    let text: String
    let done: Bool
    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold).monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(done ? Color.gold : Color.inkMuted)
            .background(done ? Color.gold.opacity(0.12) : Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RestTimerBar: View {
    let endsAt: Date
    let total: Int
    let onAdd: () -> Void
    let onDone: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, Int(endsAt.timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                    Circle().trim(from: 0, to: total > 0 ? CGFloat(left) / CGFloat(total) : 0)
                        .stroke(LinearGradient.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(left > 0 ? "REST" : "GO").font(.caption2.weight(.bold)).tracking(1.2).opacity(0.75)
                    Text(left > 0 ? "\(left / 60):\(String(format: "%02d", left % 60))" : "Next set")
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                Spacer()
                if left > 0 {
                    Button("+30s", action: onAdd).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                Button(left > 0 ? "Skip" : "OK", action: onDone).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.gold.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(left > 0 ? "Rest, \(left) seconds left" : "Rest done")
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
