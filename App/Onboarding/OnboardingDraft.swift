import Foundation
import Observation
import SwiftData
import SteadyCore

/// Everything collected during onboarding. Nothing is saved until the last
/// step, so quitting halfway leaves no partial data behind.
@Observable
@MainActor
final class OnboardingDraft {
    enum Step: Int, CaseIterable {
        case welcome, health, privacy, lock, profile, goals, experience, equipment, schedule, program, strengths,
             checkIn, nutrition, review

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .health: return "Before you start"
            case .privacy: return "Your data"
            case .lock: return "Keep it private"
            case .profile: return "About you"
            case .goals: return "Your goal"
            case .experience: return "Experience"
            case .equipment: return "Where you train"
            case .schedule: return "Your week"
            case .program: return "Your program"
            case .strengths: return "Starting strengths"
            case .checkIn: return "Weekly check-in"
            case .nutrition: return "Food targets"
            case .review: return "Your plan"
            }
        }
    }

    var step: Step = .welcome

    // health + privacy
    var acceptedDisclaimer = false
    var consents: Set<DataType> = [.profile, .training, .nutrition, .checkIns]
    // lock
    var lockEnabled = true
    var lockTimeoutSeconds = 60
    // profile
    var name = ""
    var birthYear = Calendar.current.component(.year, from: .now) - 40
    var sex: Sex = .female
    var heightCm: Double = 170
    var weightKg: Double = 70
    var bodyFatRange: String? = nil
    var perimenopause = false
    // goals / experience
    var goal: Goal = .generalHealth
    var experience: Experience = .new
    var injuries = ""
    var activity: ActivityLevel = .light
    // equipment
    var equipmentProfileId = "full_gym"
    var equipment: Set<String> = []
    // schedule
    var daysPerWeek = 3
    var preferredWeekdays: Set<Int> = [2, 5, 7]          // Mon, Thu, Sat
    var sessionMinutes = 60
    var commitments: [FixedCommitment] = []
    var avoidHeavyLegsNextToCommitments = true
    var alsoRuns = false
    // program
    var programId: String? = nil
    // strengths: lift id -> (weight, reps); reps 1 means a true 1RM
    var strengthWeight: [String: Double] = [:]
    var strengthReps: [String: Int] = [:]
    // check-in
    var checkInWeekday = 3                               // Tuesday
    var sleepGoal: Double = 8
    var stepsGoal = 10500
    var metrics: Set<String> = ["Water", "Hunger", "Digestion"]
    var dailyCheckIns = false
    // nutrition
    var presetName = MacroPreset.balanced.name
    var proteinPerKg: Double = 1.8
    var startAtMaintenance = true
    var calorieOverride: Double? = nil
    var allowBelowFloor = false

    static let bodyFatRanges = ["Not sure", "Under 15%", "15-20%", "20-25%", "25-30%", "30-35%", "Over 35%"]

    var age: Int { Calendar.current.component(.year, from: .now) - birthYear }
    var stats: BodyStats { BodyStats(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex) }
    var preset: MacroPreset { MacroPreset.all.first { $0.name == presetName } ?? .balanced }

    func applyDefaults(from content: BundledContent) {
        if equipment.isEmpty, let p = content.equipment.profile(equipmentProfileId) { equipment = Set(p.equipment) }
        if let day = weekdayNumber(content.checkIn.checkInDay) { checkInWeekday = day }
        sleepGoal = content.checkIn.sleepGoalHours
        stepsGoal = content.checkIn.dailyStepsGoal
        metrics = Set(content.checkIn.customMetricsDefault)
    }

    /// Perimenopause-aware defaults, offered as sensible starting points (all editable).
    func applyPerimenopauseDefaults() {
        proteinPerKg = max(proteinPerKg, 1.8)
        dailyCheckIns = true
        if commitments.isEmpty { avoidHeavyLegsNextToCommitments = true }
    }

    func selectEquipmentProfile(_ profile: EquipmentProfile) {
        equipmentProfileId = profile.id
        equipment = Set(profile.equipment)
    }

    func targets() -> Nutrition.Targets {
        let goalNow: Goal = startAtMaintenance ? .maintain : goal
        return Nutrition.targets(stats, activity: activity, goal: goalNow, proteinPerKg: proteinPerKg, preset: preset,
                                 calorieOverride: calorieOverride, allowBelowFloor: allowBelowFloor)
    }

    /// The goal's target once the two maintenance weeks are over.
    func goalTargets() -> Nutrition.Targets {
        Nutrition.targets(stats, activity: activity, goal: goal, proteinPerKg: proteinPerKg, preset: preset)
    }

    func oneRepMaxes() -> [String: Double] {
        var out: [String: Double] = [:]
        for (lift, w) in strengthWeight where w > 0 {
            let e = Strength.epley(weight: w, reps: strengthReps[lift] ?? 1)
            if e > 0 { out[lift] = (e * 10).rounded() / 10 }
        }
        return out
    }

    func needsStrengths(_ content: BundledContent) -> Bool {
        guard let id = programId else { return false }
        return content.program(id)?.requiresOneRepMax ?? false
    }

    var canContinue: Bool {
        switch step {
        case .health: return acceptedDisclaimer
        case .privacy: return consents.contains(.profile) && consents.contains(.training)
        case .profile: return !name.trimmingCharacters(in: .whitespaces).isEmpty && heightCm > 100 && weightKg > 30
        case .schedule: return !preferredWeekdays.isEmpty
        case .program: return programId != nil
        default: return true
        }
    }

    func next(_ content: BundledContent) {
        guard let i = Step.allCases.firstIndex(of: step), i + 1 < Step.allCases.count else { return }
        var n = Step.allCases[i + 1]
        if n == .strengths && !needsStrengths(content) { n = .checkIn }
        step = n
    }

    func back(_ content: BundledContent) {
        guard let i = Step.allCases.firstIndex(of: step), i > 0 else { return }
        var p = Step.allCases[i - 1]
        if p == .strengths && !needsStrengths(content) { p = .program }
        step = p
    }

    /// Writes everything to the store and marks onboarding complete.
    func save(into context: ModelContext, settings: AppSettings?) throws {
        let profile = UserProfile(name: name.trimmingCharacters(in: .whitespaces), birthYear: birthYear, sex: sex,
                                  heightCm: heightCm, weightKg: weightKg,
                                  bodyFatRange: bodyFatRange == "Not sure" ? nil : bodyFatRange,
                                  goal: goal, experience: experience, activity: activity, injuries: injuries,
                                  perimenopause: sex == .female && perimenopause)
        let plan = TrainingPlan(programId: programId ?? "ss-strength-foundations", startDate: Calendar.current.startOfDay(for: .now),
                                daysPerWeek: daysPerWeek, preferredWeekdays: preferredWeekdays.sorted(),
                                sessionMinutes: sessionMinutes, fixedCommitments: commitments,
                                avoidHeavyLegsNextToCommitments: avoidHeavyLegsNextToCommitments,
                                equipmentProfileId: equipmentProfileId, equipment: equipment.sorted(),
                                oneRepMaxes: oneRepMaxes())
        let nutrition = NutritionPlan(targets: targets(), presetName: presetName, proteinPerKg: proteinPerKg,
                                      startAtMaintenance: startAtMaintenance)
        let checkIn = CheckInSettings(weekday: checkInWeekday, sleepGoalHours: sleepGoal, stepsGoal: stepsGoal,
                                      metrics: metrics.sorted(), dailyCheckIns: dailyCheckIns)
        let s = settings ?? AppSettings()
        if settings == nil { context.insert(s) }
        s.disclaimerAcceptedAt = .now
        s.consents = Dictionary(uniqueKeysWithValues: consents.map { ($0.rawValue, Date.now) })
        s.lockEnabled = lockEnabled
        s.lockTimeoutSeconds = lockTimeoutSeconds
        context.insert(profile)
        context.insert(plan)
        context.insert(nutrition)
        context.insert(checkIn)
        s.onboardingComplete = true
        try context.save()
    }
}

let weekdayNames = Calendar.current.weekdaySymbols          // index 0 = Sunday
let weekdayShortNames = Calendar.current.shortWeekdaySymbols

func weekdayNumber(_ name: String) -> Int? {
    weekdayNames.firstIndex { $0.lowercased() == name.lowercased() }.map { $0 + 1 }
}
