import SwiftUI
import SwiftData
import SteadyCore

struct OnboardingFlow: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query private var settings: [AppSettings]
    @State private var draft = OnboardingDraft()
    @State private var saveError: String?
    @State private var prepared = false

    var body: some View {
        if let content = store.content {
            NavigationStack {
                VStack(spacing: 0) {
                    ProgressView(value: Double(draft.step.rawValue), total: Double(OnboardingDraft.Step.allCases.count - 1))
                        .padding(.horizontal)
                        .accessibilityLabel("Step \(draft.step.rawValue + 1) of \(OnboardingDraft.Step.allCases.count)")
                    stepView(content)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    footer(content)
                }
                .themedList()
                .navigationTitle(draft.step.title)
                .navigationBarTitleDisplayMode(.inline)
                .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
                    Button("OK") { saveError = nil }
                } message: { Text(saveError ?? "") }
            }
            .onAppear {
                if !prepared { draft.applyDefaults(from: content); prepared = true }
            }
        }
    }

    @ViewBuilder
    private func stepView(_ content: BundledContent) -> some View {
        switch draft.step {
        case .welcome: WelcomeStep()
        case .health: HealthStep(draft: draft)
        case .privacy: PrivacyStep(draft: draft)
        case .lock: LockStep(draft: draft)
        case .profile: ProfileStep(draft: draft)
        case .goals: GoalStep(draft: draft)
        case .experience: ExperienceStep(draft: draft)
        case .equipment: EquipmentStep(draft: draft, catalog: content.equipment)
        case .schedule: ScheduleStep(draft: draft)
        case .program: ProgramStep(draft: draft, content: content)
        case .strengths: StrengthsStep(draft: draft)
        case .checkIn: CheckInStep(draft: draft, options: content.checkIn.customMetricOptions)
        case .nutrition: NutritionStep(draft: draft)
        case .review: ReviewStep(draft: draft, content: content)
        }
    }

    private func footer(_ content: BundledContent) -> some View {
        HStack(spacing: 12) {
            if draft.step != .welcome {
                Button("Back") { withAnimation { draft.back(content) } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboardingBack")
            }
            Button {
                if draft.step == .review {
                    do { try draft.save(into: context, settings: settings.first) } catch { saveError = error.localizedDescription }
                } else {
                    withAnimation { draft.next(content) }
                }
            } label: {
                Text(draft.step == .review ? "Start my plan" : draft.step == .welcome ? "Get started" : "Continue")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canContinue)
            .accessibilityIdentifier("onboardingNext")
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Steps

struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                Text("Steady Strength")
                    .font(.largeTitle.bold())
                Text("Strength training that adapts to your week, your energy and your gym, with food and weekly check-ins in one place.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Programs that progress your weights for you", systemImage: "chart.line.uptrend.xyaxis")
                    Label("Swaps for any exercise when equipment isn't free", systemImage: "arrow.triangle.swap")
                    Label("Shorter versions for busy or low-energy days", systemImage: "clock")
                    Label("Your data stays on this phone", systemImage: "lock.shield")
                }
                .font(.body)
            }
            .padding()
        }
    }
}

struct HealthStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section {
                Text("Check with your doctor before starting a new exercise or nutrition program, especially if you have a medical condition, an injury, are pregnant, or haven't exercised for a while.")
                Text("Steady Strength gives general training and nutrition guidance. It isn't medical advice and doesn't diagnose anything.")
            }
            Section("Stop and get checked if you have") {
                Text("Chest pain, fainting or severe dizziness, unusual breathlessness, palpitations, sharp or lasting joint pain, pelvic heaviness or leaking, or unusually heavy bleeding.")
            }
            Section {
                Toggle("I understand", isOn: $draft.acceptedDisclaimer)
                    .accessibilityIdentifier("acceptDisclaimer")
            }
        }
    }
}

struct PrivacyStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section {
                Text("Your health information is stored only on this iPhone, encrypted by iOS. It is never sold or used for advertising, and nothing is sent to any server without asking you first.")
                NavigationLink("Read the privacy policy") { PrivacyPolicyView() }
            }
            Section("Choose what the app may keep") {
                ForEach(DataType.allCases) { type in
                    Toggle(isOn: Binding(
                        get: { draft.consents.contains(type) },
                        set: { on in if on { draft.consents.insert(type) } else { draft.consents.remove(type) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.title)
                            Text(type.required ? "Needed for the app to work. \(type.detail)" : type.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(type.required || type == .appleHealth)
                }
            }
        }
    }
}

struct LockStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section {
                Toggle("Lock with \(AppLock.biometryName)", isOn: $draft.lockEnabled)
                Picker("Lock after", selection: $draft.lockTimeoutSeconds) {
                    ForEach(LockPolicy.timeoutChoices, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                .disabled(!draft.lockEnabled)
            } footer: {
                Text("The app locks when you leave it for this long and unlocks with \(AppLock.biometryName) or your passcode. The app never sees your face; iOS only tells it that you unlocked.")
            }
        }
    }
}

struct ProfileStep: View {
    @Bindable var draft: OnboardingDraft
    private let years = Array((1940...(Calendar.current.component(.year, from: .now) - 16)).reversed())

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $draft.name)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("nameField")
                Picker("Year of birth", selection: $draft.birthYear) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                Picker("Sex", selection: $draft.sex) {
                    ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: { Text("Used to estimate your energy needs.") }
            Section("Body") {
                Stepper(value: $draft.heightCm, in: 120...220, step: 1) {
                    LabeledContent("Height", value: "\(Int(draft.heightCm)) cm")
                }
                Stepper(value: $draft.weightKg, in: 35...250, step: 0.5) {
                    LabeledContent("Weight", value: String(format: "%.1f kg", draft.weightKg))
                }
                Picker("Body fat (optional)", selection: Binding(get: { draft.bodyFatRange ?? "Not sure" },
                                                                 set: { draft.bodyFatRange = $0 })) {
                    ForEach(OnboardingDraft.bodyFatRanges, id: \.self) { Text($0).tag($0) }
                }
            }
            if draft.sex == .female {
                Section {
                    Toggle("I'm perimenopausal or menopausal", isOn: $draft.perimenopause)
                        .onChange(of: draft.perimenopause) { _, on in if on { draft.applyPerimenopauseDefaults() } }
                } footer: {
                    Text("Optional. Turns on defaults suited to this stage: heavier strength work, higher protein, a trend line for weight, and private daily check-ins for energy, sleep and symptoms. You can change any of them.")
                }
            }
        }
    }
}

struct GoalStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section("Main goal") {
                Picker("Goal", selection: $draft.goal) {
                    ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Activity outside training") {
                Picker("Activity", selection: $draft.activity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        VStack(alignment: .leading) {
                            Text(level.label)
                            Text(level.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }
}

struct ExperienceStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section("Strength training experience") {
                Picker("Experience", selection: $draft.experience) {
                    ForEach(Experience.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                TextField("Injuries or limitations (optional)", text: $draft.injuries, axis: .vertical)
                    .lineLimit(2...5)
            } footer: { Text("For example: sore left knee, no overhead pressing. Shown on your plan so you can swap exercises.") }
        }
    }
}

struct EquipmentStep: View {
    @Bindable var draft: OnboardingDraft
    let catalog: EquipmentCatalog
    var body: some View {
        Form {
            Section {
                ForEach(catalog.profiles) { profile in
                    Button {
                        draft.selectEquipmentProfile(profile)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).foregroundStyle(.primary)
                                Text(profile.description).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if draft.equipmentProfileId == profile.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(draft.equipmentProfileId == profile.id ? .isSelected : [])
                }
            } header: { Text("Where do you usually train?") } footer: {
                Text("When something isn't available, or is busy, the app swaps in the closest exercise. You can change this any day, for example in a hotel.")
            }
            Section("Fine-tune what's there") {
                ForEach(catalog.sortedItems, id: \.id) { item in
                    Toggle(item.name, isOn: Binding(
                        get: { draft.equipment.contains(item.id) },
                        set: { on in if on { draft.equipment.insert(item.id) } else { draft.equipment.remove(item.id) } }))
                }
            }
        }
    }
}

struct ScheduleStep: View {
    @Bindable var draft: OnboardingDraft
    @State private var newName = "Yoga"
    @State private var newDay = 3

    var body: some View {
        Form {
            Section {
                Stepper("\(draft.daysPerWeek) strength days a week", value: $draft.daysPerWeek, in: 2...6)
                Picker("Session length", selection: $draft.sessionMinutes) {
                    Text("About 45 minutes").tag(45)
                    Text("About 60 minutes").tag(60)
                    Text("About 75 minutes").tag(75)
                }
            }
            Section {
                ForEach(1...7, id: \.self) { day in
                    Toggle(weekdayNames[day - 1], isOn: Binding(
                        get: { draft.preferredWeekdays.contains(day) },
                        set: { on in if on { draft.preferredWeekdays.insert(day) } else { draft.preferredWeekdays.remove(day) } }))
                }
            } header: { Text("Days you'd like to train") } footer: {
                Text("Your plan is a rotation, not fixed days: if you miss a day, the next session simply moves to your next free day.")
            }
            Section {
                ForEach(draft.commitments) { c in
                    LabeledContent(c.name, value: "\(weekdayNames[c.weekday - 1]), \(c.minutes) min")
                }
                .onDelete { draft.commitments.remove(atOffsets: $0) }
                HStack {
                    TextField("Activity", text: $newName)
                    Picker("Day", selection: $newDay) {
                        ForEach(1...7, id: \.self) { Text(weekdayShortNames[$0 - 1]).tag($0) }
                    }
                    .labelsHidden()
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        draft.commitments.append(FixedCommitment(name: name, weekday: newDay, minutes: 60))
                        draft.preferredWeekdays.remove(newDay)
                    }
                }
                if !draft.commitments.isEmpty {
                    Toggle("Keep heavy leg work off the days either side", isOn: $draft.avoidHeavyLegsNextToCommitments)
                }
            } header: { Text("Fixed activities") } footer: {
                Text("Classes like yoga or Pilates, or sport. They count towards your weekly activity and strength days are planned around them.")
            }
            Section {
                Toggle("I also run (about 3 times a week)", isOn: $draft.alsoRuns)
            } footer: { Text("Runs are read from Apple Health in a later update, and heavy leg days are kept away from key runs.") }
        }
    }
}

struct ProgramStep: View {
    @Bindable var draft: OnboardingDraft
    let content: BundledContent

    var body: some View {
        let recs = ProgramAdvisor.recommend(experience: draft.experience, daysPerWeek: draft.daysPerWeek, programs: content.programs)
        let recIds = recs.map(\.programId)
        let others = content.programs.filter { !recIds.contains($0.id) }
        Form {
            Section("Suggested for you") {
                ForEach(recs, id: \.programId) { rec in
                    if let p = content.program(rec.programId) { row(p, reason: rec.reason) }
                }
            }
            Section("All programs") {
                ForEach(others) { row($0, reason: nil) }
            }
        }
        .onAppear { if draft.programId == nil { draft.programId = recIds.first } }
    }

    private func row(_ p: Program, reason: String?) -> some View {
        Button {
            draft.programId = p.id
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).foregroundStyle(.primary)
                    Text("\(p.weeks.count) weeks · \(p.sessionsPerWeekText) sessions a week · about \(p.averageSessionMinutes) min")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let text = reason ?? p.description { Text(text).font(.footnote).foregroundStyle(.secondary) }
                    if let cov = p.equipmentCoverage[draft.equipmentProfileId], cov.swapped > 0 {
                        Text("\(cov.swapped) of \(cov.total) exercises swapped for your equipment")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if draft.programId == p.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .accessibilityAddTraits(draft.programId == p.id ? .isSelected : [])
        .accessibilityIdentifier("program-\(p.id)")
    }
}

struct StrengthsStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        Form {
            Section {
                Text("This program sets weights from a percentage of your best single lift (1RM). Enter a recent 1RM, or a weight and the reps you did with it and the app estimates it. Leave any blank to test it in week 1.")
                    .font(.callout)
            }
            ForEach(Strength.oneRepMaxLifts, id: \.id) { lift in
                Section(lift.name) {
                    HStack {
                        Text("Weight")
                        TextField("kg", value: Binding(get: { draft.strengthWeight[lift.id] },
                                                       set: { draft.strengthWeight[lift.id] = $0 }), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    Stepper("Reps: \(draft.strengthReps[lift.id] ?? 1)", value: Binding(
                        get: { draft.strengthReps[lift.id] ?? 1 }, set: { draft.strengthReps[lift.id] = $0 }), in: 1...12)
                    if let w = draft.strengthWeight[lift.id], w > 0 {
                        let e = Strength.epley(weight: w, reps: draft.strengthReps[lift.id] ?? 1)
                        LabeledContent("Estimated 1RM", value: String(format: "%.1f kg", e))
                    }
                }
            }
        }
    }
}

struct CheckInStep: View {
    @Bindable var draft: OnboardingDraft
    let options: [String]
    var body: some View {
        Form {
            Section {
                Picker("Check-in day", selection: $draft.checkInWeekday) {
                    ForEach(1...7, id: \.self) { Text(weekdayNames[$0 - 1]).tag($0) }
                }
                Stepper(value: $draft.sleepGoal, in: 5...10, step: 0.5) {
                    LabeledContent("Sleep goal", value: String(format: "%g hours", draft.sleepGoal))
                }
                Stepper(value: $draft.stepsGoal, in: 2000...20000, step: 500) {
                    LabeledContent("Daily steps goal", value: draft.stepsGoal.formatted())
                }
            } footer: { Text("Once a week you review your averages, measurements and photos.") }
            Section {
                ForEach(options, id: \.self) { m in
                    Toggle(m, isOn: Binding(
                        get: { draft.metrics.contains(m) },
                        set: { on in
                            if on, draft.metrics.count < 3 { draft.metrics.insert(m) } else if !on { draft.metrics.remove(m) }
                        }))
                }
            } header: { Text("Daily 1-10 ratings (up to 3)") }
            Section {
                Toggle("Daily check-in: energy, sleep quality, mood, symptoms", isOn: $draft.dailyCheckIns)
            } footer: { Text("Optional and private to this phone. Helps you spot patterns against training and weight.") }
        }
    }
}

struct NutritionStep: View {
    @Bindable var draft: OnboardingDraft
    var body: some View {
        let t = draft.targets()
        Form {
            Section {
                LabeledContent("Estimated maintenance", value: "\(t.maintenance) kcal")
                Toggle("Start at maintenance for 2 weeks", isOn: $draft.startAtMaintenance)
            } footer: {
                Text("The estimate is a starting point. Two weeks of logging shows your real maintenance; after that the app suggests your \(draft.goal.label.lowercased()) target and keeps adjusting it from your weight trend.")
            }
            Section("Daily targets") {
                LabeledContent("Calories", value: "\(t.calories) kcal")
                LabeledContent("Protein", value: "\(t.protein) g")
                LabeledContent("Carbohydrate", value: "\(t.carbs) g")
                LabeledContent("Fat", value: "\(t.fat) g")
                LabeledContent("Fibre", value: "\(t.fibre) g")
                if draft.startAtMaintenance, draft.goal != .maintain, draft.goal != .generalHealth {
                    LabeledContent("After 2 weeks", value: "\(draft.goalTargets().calories) kcal")
                }
            }
            Section {
                Stepper(value: $draft.proteinPerKg, in: 1.2...2.4, step: 0.1) {
                    LabeledContent("Protein", value: String(format: "%.1f g per kg", draft.proteinPerKg))
                }
                Picker("Eating style", selection: $draft.presetName) {
                    ForEach(MacroPreset.all) { Text($0.name).tag($0.name) }
                }
            } footer: { Text("Protein is set first from your body weight; the eating style then shapes carbs and fat.") }
            ForEach(Array(t.warnings.enumerated()), id: \.offset) { _, w in
                Section { Label(text(for: w), systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
        }
    }

    private func text(for w: Nutrition.Warning) -> String {
        switch w {
        case .raisedToFloor(let f): return "Your target was raised to \(f) kcal, the lowest the app sets without an override. Slower and steadier works better long term."
        case .belowFloor(let f): return "This is below \(f) kcal a day. Please check it with your doctor or dietitian."
        case .fatLowered: return "There wasn't room for this eating style's fat after protein, so fat was lowered."
        case .proteinAbovePreset: return "Protein is higher than this eating style suggests, because your protein target comes first."
        }
    }
}

struct ReviewStep: View {
    @Bindable var draft: OnboardingDraft
    let content: BundledContent
    var body: some View {
        let t = draft.targets()
        let program = draft.programId.flatMap { content.program($0) }
        Form {
            Section("Training") {
                LabeledContent("Program", value: program?.name ?? "-")
                LabeledContent("Days", value: draft.preferredWeekdays.sorted().map { weekdayShortNames[$0 - 1] }.joined(separator: ", "))
                LabeledContent("Equipment", value: content.equipment.profile(draft.equipmentProfileId)?.name ?? "Custom")
                if let first = program?.weeks.first?.workouts.first {
                    LabeledContent("First session", value: "\(first.name), about \(first.estimatedMinutes) min")
                }
                ForEach(draft.commitments) { c in
                    LabeledContent(c.name, value: weekdayNames[c.weekday - 1])
                }
            }
            Section("Food") {
                LabeledContent("Calories", value: "\(t.calories) kcal")
                LabeledContent("Protein", value: "\(t.protein) g")
            }
            Section("Check-in") {
                LabeledContent("Day", value: weekdayNames[draft.checkInWeekday - 1])
                LabeledContent("Sleep goal", value: String(format: "%g h", draft.sleepGoal))
                LabeledContent("Steps goal", value: draft.stepsGoal.formatted())
            }
            Section {
                Text("Apple Health, calendar, reminders and Strava are set up in later updates. Everything here can be changed in Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
