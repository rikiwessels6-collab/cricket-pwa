import SwiftUI
import SwiftData
import SteadyCore

/// Changing your goal. Your history is kept; calorie and macro targets are worked out again for the new goal.
enum GoalSwitch {
    static func targets(for goal: Goal, profile: UserProfile, nutrition: NutritionPlan) -> Nutrition.Targets {
        let preset = MacroPreset.all.first { $0.name == nutrition.presetName } ?? .balanced
        return Nutrition.targets(profile.stats, activity: profile.activity, goal: goal,
                                 proteinPerKg: nutrition.proteinPerKg, preset: preset)
    }

    static func apply(_ goal: Goal, profile: UserProfile, nutrition: NutritionPlan?, today: Date = .now) {
        profile.goalRaw = goal.rawValue
        profile.goalChangedAt = today
        guard let n = nutrition else { return }
        let t = targets(for: goal, profile: profile, nutrition: n)
        n.calories = t.calories
        n.protein = t.protein
        n.carbs = t.carbs
        n.fat = t.fat
        n.fibre = t.fibre
        n.maintenance = t.maintenance
        // The two-weeks-at-maintenance start only applies to a brand new plan.
        n.startAtMaintenance = false
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
    @State private var chosen: Goal?

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
                        let t = GoalSwitch.targets(for: goal, profile: p, nutrition: n)
                        Section {
                            compare("Calories", old: n.calories, new: t.calories, unit: "kcal")
                            compare("Protein", old: n.protein, new: t.protein, unit: "g")
                            compare("Carbs", old: n.carbs, new: t.carbs, unit: "g")
                            compare("Fat", old: n.fat, new: t.fat, unit: "g")
                            if t.warnings.contains(where: { if case .raisedToFloor = $0 { return true } else { return false } }) {
                                Text("Your target was raised to the lowest daily amount this app sets (\(Int(Nutrition.safeFloor(p.sex))) kcal).")
                                    .font(.footnote).foregroundStyle(Color.gold)
                            }
                        } header: { Text("Your new daily targets") } footer: {
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
                                GoalSwitch.apply(goal, profile: p, nutrition: nutrition.first)
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
