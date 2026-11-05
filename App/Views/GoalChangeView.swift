import SwiftUI
import SwiftData
import SteadyCore

/// Changing your goal. Your history is kept; calorie and macro targets are worked out again for the new goal.
enum GoalSwitch {
    static let easeInDays = 14

    /// Targets for a goal. `weightKg` overrides the profile weight (for a preview before it is saved).
    static func targets(for goal: Goal, profile: UserProfile, nutrition: NutritionPlan, weightKg: Double? = nil) -> Nutrition.Targets {
        let preset = MacroPreset.all.first { $0.name == nutrition.presetName } ?? .balanced
        var stats = profile.stats
        if let w = weightKg { stats.weightKg = w }
        return Nutrition.targets(stats, activity: profile.activity, goal: goal,
                                 proteinPerKg: nutrition.proteinPerKg, preset: preset)
    }

    /// Only goals with a deficit or surplus are eased into.
    static func canEaseIn(_ goal: Goal) -> Bool { goal == .fatLoss || goal == .buildMuscle }

    private static func copy(_ t: Nutrition.Targets, into n: NutritionPlan) {
        n.calories = t.calories
        n.protein = t.protein
        n.carbs = t.carbs
        n.fat = t.fat
        n.fibre = t.fibre
        n.maintenance = t.maintenance
    }

    /// Saves the goal. With `easeIn`, targets stay at maintenance for two weeks and then step to the goal's targets.
    /// `weightKg` (from your latest check-in) replaces the weight on your profile first.
    static func apply(_ goal: Goal, profile: UserProfile, nutrition: NutritionPlan?, easeIn: Bool = false,
                      weightKg: Double? = nil, today: Date = .now) {
        if let w = weightKg, (30...300).contains(w) { profile.weightKg = w }
        profile.goalRaw = goal.rawValue
        profile.goalChangedAt = today
        guard let n = nutrition else { return }
        if easeIn && canEaseIn(goal) {
            copy(targets(for: .maintain, profile: profile, nutrition: n), into: n)
            n.startAtMaintenance = true
            n.easeInUntil = Calendar.current.date(byAdding: .day, value: easeInDays, to: today)
        } else {
            copy(targets(for: goal, profile: profile, nutrition: n), into: n)
            n.startAtMaintenance = false
            n.easeInUntil = nil
        }
    }

    /// Steps from maintenance to the goal's targets once the two weeks are over. For plans made in onboarding
    /// (which have no end date) the two weeks run from when the plan was created. Returns true if it changed anything.
    @discardableResult
    static func finishEaseInIfDue(profile: UserProfile, nutrition: NutritionPlan, now: Date = .now) -> Bool {
        guard nutrition.startAtMaintenance else { return false }
        let due = nutrition.easeInUntil
            ?? Calendar.current.date(byAdding: .day, value: easeInDays, to: nutrition.createdAt) ?? nutrition.createdAt
        guard now >= due else { return false }
        copy(targets(for: profile.goal, profile: profile, nutrition: nutrition), into: nutrition)
        nutrition.startAtMaintenance = false
        nutrition.easeInUntil = nil
        return true
    }

    /// Programs in the catalogue tagged for this goal.
    static func programs(for goal: Goal, in catalogue: [Program]) -> [Program] {
        catalogue.filter { ($0.goalTags ?? []).contains(goal.programTag) }
    }
}

struct GoalChangeView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var nutrition: [NutritionPlan]
    @Query(sort: \CheckInEntry.date, order: .reverse) private var checkIns: [CheckInEntry]
    @State private var chosen: Goal?
    @State private var easeIn = true
    @State private var useCheckInWeight = true

    /// The latest check-in weight, if it differs from the weight on your profile.
    private func newerWeight(_ p: UserProfile) -> CheckInEntry? {
        guard let e = checkIns.first(where: { $0.weightKg != nil }), let w = e.weightKg,
              (30...300).contains(w), abs(w - p.weightKg) >= 0.1 else { return nil }
        return e
    }

    var body: some View {
        NavigationStack {
            if let p = profiles.first {
                let goal = chosen ?? p.goal
                Form {
                    Section {
                        ForEach(Goal.allCases, id: \.self) { g in
                            Button { chosen = g } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(g.label).foregroundStyle(.primary)
                                        Text(g.summary).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if goal == g { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                            .accessibilityAddTraits(goal == g ? .isSelected : [])
                            .accessibilityIdentifier("goal-\(g.rawValue)")
                        }
                    } header: { Text("Why are you training?") } footer: {
                        if let at = p.goalChangedAt {
                            Text("Last changed \(at.formatted(date: .abbreviated, time: .omitted)). Your history is kept.")
                        } else {
                            Text("You can change this any time. Your history is kept.")
                        }
                    }
                    if goal != p.goal, let n = nutrition.first {
                        let entry = newerWeight(p)
                        let weight = (useCheckInWeight ? entry?.weightKg : nil)
                        let easing = easeIn && GoalSwitch.canEaseIn(goal)
                        let goalTargets = GoalSwitch.targets(for: goal, profile: p, nutrition: n, weightKg: weight)
                        let now = easing ? GoalSwitch.targets(for: .maintain, profile: p, nutrition: n, weightKg: weight) : goalTargets
                        if let entry, let w = entry.weightKg {
                            Section {
                                Toggle("Use my latest check-in weight", isOn: $useCheckInWeight)
                            } footer: {
                                Text("Your profile says \(NumberText.format(p.weightKg)) kg. Your check-in on \(entry.date.formatted(date: .abbreviated, time: .omitted)) says \(NumberText.format(w)) kg. Targets are worked out from the weight you choose.")
                            }
                        }
                        if GoalSwitch.canEaseIn(goal) {
                            Section {
                                Toggle("Ease in: two weeks at maintenance first", isOn: $easeIn)
                                    .accessibilityIdentifier("easeIn")
                            } footer: {
                                Text("Starts at your maintenance calories for two weeks, then steps up to the \(goal.label.lowercased()) targets automatically. Switch it off to start the new targets today.")
                            }
                        }
                        Section {
                            compare("Calories", old: n.calories, new: now.calories, unit: "kcal")
                            compare("Protein", old: n.protein, new: now.protein, unit: "g")
                            compare("Carbs", old: n.carbs, new: now.carbs, unit: "g")
                            compare("Fat", old: n.fat, new: now.fat, unit: "g")
                            if easing {
                                Text("After two weeks: \(goalTargets.calories.formatted()) kcal a day.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            if goalTargets.warnings.contains(where: { if case .raisedToFloor = $0 { return true } else { return false } }) {
                                Text("Your target was raised to the lowest daily amount this app sets (\(Int(Nutrition.safeFloor(p.sex))) kcal).")
                                    .font(.footnote).foregroundStyle(Color.gold)
                            }
                        } header: { Text(easing ? "Your daily targets from today" : "Your new daily targets") } footer: {
                            Text("These come from your weight, height, age and activity level. They are a starting point; adjust them from your check-ins.")
                        }
                    }
                    if let content = store.content {
                        let fits = GoalSwitch.programs(for: goal, in: content.catalogue(showDraft: AppConfig.showDraft))
                        if !fits.isEmpty {
                            Section {
                                ForEach(fits) { Text($0.name) }
                            } header: { Text("Programs that suit this goal") } footer: {
                                Text("Your program stays as it is until you change it in Settings, under Program.")
                            }
                        }
                    }
                    if goal != p.goal {
                        Section {
                            Button("Save my goal") {
                                GoalSwitch.apply(goal, profile: p, nutrition: nutrition.first, easeIn: easeIn,
                                                 weightKg: useCheckInWeight ? newerWeight(p)?.weightKg : nil)
                                try? context.save()
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("saveGoal")
                        }
                    }
                }
                .navigationTitle("Your goal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            } else {
                ProgressView()
            }
        }
    }

    private func compare(_ label: String, old: Int, new: Int, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(old.formatted()) → \(new.formatted()) \(unit)")
                .monospacedDigit().foregroundStyle(old == new ? Color.secondary : Color.gold)
        }
        .accessibilityElement(children: .combine)
    }
}
