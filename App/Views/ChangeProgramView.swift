import SwiftUI
import SwiftData
import SteadyCore

/// Switching programs. Your history is kept; the new program starts at week 1.
enum ProgramSwitch {
    /// Points the plan at a new program from week 1. 1RMs entered here are merged in (blank ones are kept as they were).
    static func apply(_ plan: TrainingPlan, to program: Program, oneRepMaxes: [String: Double] = [:], today: Date = .now) {
        plan.programId = program.id
        plan.nextSessionIndex = 0
        plan.startDate = Calendar.current.startOfDay(for: today)
        for (lift, kg) in oneRepMaxes where kg > 0 { plan.oneRepMaxes[lift] = kg }
    }
}

struct ChangeProgramView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [TrainingPlan]
    @Query private var profiles: [UserProfile]
    @State private var chosen: Program?
    @State private var confirming = false
    @State private var oneRepMaxes: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if let content = store.content, let plan = plans.first {
                    let all = content.catalogue(showDraft: AppConfig.showDraft)
                    let recs = profiles.first.map {
                        ProgramAdvisor.recommend(experience: $0.experience, daysPerWeek: plan.daysPerWeek, programs: all)
                    } ?? []
                    let recIds = recs.map(\.programId)
                    List {
                        if !recs.isEmpty {
                            Section("Suggested for you") {
                                ForEach(recs, id: \.programId) { rec in
                                    if let p = content.program(rec.programId) { row(p, plan: plan, reason: rec.reason) }
                                }
                            }
                        }
                        Section("All programs") {
                            ForEach(all.filter { !recIds.contains($0.id) }) { row($0, plan: plan, reason: nil) }
                        }
                    }
                    .themedList()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Change program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $chosen) { program in
                SwitchConfirmSheet(program: program, oneRepMaxes: $oneRepMaxes) {
                    if let plan = plans.first {
                        ProgramSwitch.apply(plan, to: program, oneRepMaxes: oneRepMaxes)
                        try? context.save()
                    }
                    chosen = nil
                    dismiss()
                }
            }
        }
    }

    private func row(_ p: Program, plan: TrainingPlan, reason: String?) -> some View {
        Button { chosen = p } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).foregroundStyle(.primary)
                    Text("\(p.weeks.count) weeks · \(p.sessionsPerWeekText) sessions a week · about \(p.averageSessionMinutes) min")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let text = reason ?? p.description { Text(text).font(.footnote).foregroundStyle(.secondary) }
                    if let cov = p.equipmentCoverage[plan.equipmentProfileId], cov.swapped > 0 {
                        Text("\(cov.swapped) of \(cov.total) exercises swapped for your equipment").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if plan.programId == p.id { Label("Current", systemImage: "checkmark").labelStyle(.titleAndIcon).font(.caption).foregroundStyle(Color.gold) }
            }
        }
        .accessibilityIdentifier("switch-\(p.id)")
    }
}

extension Program: @retroactive Hashable {
    public static func == (a: Program, b: Program) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct SwitchConfirmSheet: View {
    let program: Program
    @Binding var oneRepMaxes: [String: Double]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(program.name).font(.title3.weight(.semibold))
                    Text("You'll start at week 1. Everything you've logged so far is kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if program.requiresOneRepMax {
                    Section {
                        ForEach(Strength.oneRepMaxLifts, id: \.id) { lift in
                            HStack {
                                Text(lift.name)
                                TextField("kg", value: Binding(get: { oneRepMaxes[lift.id] }, set: { oneRepMaxes[lift.id] = $0 }), format: .number)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                Text("kg").foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text("Your best single lift (1RM)") } footer: {
                        Text("This program sets weights from a percentage of your 1RM. Leave a lift blank to test it in week 1, or keep the number you entered before.")
                    }
                }
                Section {
                    Button("Switch to this program") { onConfirm() }.fontWeight(.semibold)
                        .accessibilityIdentifier("confirmSwitch")
                }
            }
            .navigationTitle("Switch program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
