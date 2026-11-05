import Foundation

// Codable mirrors of exercise_library.json, equipment.json and
// checkin_defaults.json, plus a single loader for all bundled content.

public struct ExerciseLibrary: Decodable, Sendable {
    public let schemaVersion: Int
    public let patterns: [String: String]
    public let muscles: [String]
    public let exercises: [Exercise]
}

public struct Exercise: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pattern: String
    public let tier: String
    public let equipment: [String]
    public let primaryMuscles: [String]
    public let secondaryMuscles: [String]
    public let unilateral: Bool
    public let loadable: Bool
    public let timed: Bool
    public let difficulty: Int
    public let oneRepMaxLift: String?
    public let cues: String
    public let cueSource: String
    public let seed: Bool
    public let swapText: String?
    public let aliases: [String]
    public let demoSearchQuery: String
    public let advancedTip: String?
    /// Advanced movements get a review prompt and easier options.
    public let contraindicationReviewFlag: Bool?
    public let easierRegression: [String]?
    public let video: VideoInfo?
    public let substitutes: [Substitute]
    public let usedIn: [String]

    public var isMainLift: Bool { tier == "main" }

    /// An exercise the user adds themselves. It has no form cues, video or curated swaps.
    public static func custom(id: String, name: String, primaryMuscle: String, secondaryMuscle: String?,
                              equipment: [String], loadable: Bool, unilateral: Bool, timed: Bool) -> Exercise {
        Exercise(id: id, name: name, pattern: "custom", tier: "accessory", equipment: equipment,
                 primaryMuscles: [primaryMuscle], secondaryMuscles: secondaryMuscle.map { [$0] } ?? [],
                 unilateral: unilateral, loadable: loadable, timed: timed, difficulty: 1, oneRepMaxLift: nil,
                 cues: "", cueSource: "", seed: false, swapText: nil, aliases: [],
                 demoSearchQuery: name + " exercise", advancedTip: nil, contraindicationReviewFlag: nil,
                 easierRegression: nil, video: nil, substitutes: [], usedIn: [])
    }

    public var isCustom: Bool { pattern == "custom" }

    init(id: String, name: String, pattern: String, tier: String, equipment: [String], primaryMuscles: [String],
         secondaryMuscles: [String], unilateral: Bool, loadable: Bool, timed: Bool, difficulty: Int,
         oneRepMaxLift: String?, cues: String, cueSource: String, seed: Bool, swapText: String?, aliases: [String],
         demoSearchQuery: String, advancedTip: String?, contraindicationReviewFlag: Bool?, easierRegression: [String]?,
         video: VideoInfo?, substitutes: [Substitute], usedIn: [String]) {
        self.id = id; self.name = name; self.pattern = pattern; self.tier = tier; self.equipment = equipment
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles; self.unilateral = unilateral
        self.loadable = loadable; self.timed = timed; self.difficulty = difficulty; self.oneRepMaxLift = oneRepMaxLift
        self.cues = cues; self.cueSource = cueSource; self.seed = seed; self.swapText = swapText; self.aliases = aliases
        self.demoSearchQuery = demoSearchQuery; self.advancedTip = advancedTip
        self.contraindicationReviewFlag = contraindicationReviewFlag; self.easierRegression = easierRegression
        self.video = video; self.substitutes = substitutes; self.usedIn = usedIn
    }
}

/// No video is approved until its licence, owner and evidence are recorded; until then the app only offers a search link.
public struct VideoInfo: Decodable, Sendable {
    public let status: String
    public var isApproved: Bool { status == "approved" }
}

public struct Substitute: Decodable, Sendable {
    public let id: String
    public let score: Double
    public let curated: Bool
    public let samePattern: Bool
}

public struct EquipmentCatalog: Decodable, Sendable {
    public let equipment: [String: String]
    public let alwaysAvailable: [String]
    public let profiles: [EquipmentProfile]

    public func profile(_ id: String) -> EquipmentProfile? { profiles.first { $0.id == id } }

    /// Equipment ids sorted by their display name, for settings lists.
    public var sortedItems: [(id: String, name: String)] {
        equipment.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }
}

public struct EquipmentProfile: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let equipment: [String]
}

public struct CheckInDefaults: Decodable, Sendable {
    public struct Preset: Decodable, Sendable {
        public let name: String
        public let protein: Double
        public let carbs: Double
        public let fat: Double
    }
    public struct Peri: Decodable, Sendable {
        public let carbShare: Double
        public let fatShare: Double
    }
    public struct MealFrequency: Decodable, Sendable {
        public let trainingDay: Int
        public let restDay: Int
    }
    public let checkInDay: String
    public let sleepGoalHours: Double
    public let dailyStepsGoal: Int
    public let customMetricOptions: [String]
    public let customMetricsDefault: [String]
    public let measurementSites: [String]
    public let dietaryPresets: [Preset]
    public let activityFactors: [String: Double]
    public let fibrePer1000kcal: Double
    public let periWorkout: Peri
    public let mealFrequency: MealFrequency
}

/// Everything the app ships in Resources/Generated, decoded together.
public struct BundledContent: Sendable {
    public let programs: [Program]
    public let library: [String: Exercise]
    public let patterns: [String: String]
    public let equipment: EquipmentCatalog
    public let checkIn: CheckInDefaults

    public init(programs: Data, library: Data, equipment: Data, checkIn: Data) throws {
        let d = JSONDecoder()
        self.programs = try d.decode(ProgramBundle.self, from: programs).programs
        let lib = try d.decode(ExerciseLibrary.self, from: library)
        self.library = Dictionary(uniqueKeysWithValues: lib.exercises.map { ($0.id, $0) })
        self.patterns = lib.patterns
        self.equipment = try d.decode(EquipmentCatalog.self, from: equipment)
        self.checkIn = try d.decode(CheckInDefaults.self, from: checkIn)
    }

    /// Loads the four JSON files from a directory (tests) or bundle resource URLs.
    public init(directory: URL) throws {
        func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        try self.init(programs: read("programs.json"), library: read("exercise_library.json"),
                      equipment: read("equipment.json"), checkIn: read("checkin_defaults.json"))
    }

    private init(programs: [Program], library: [String: Exercise], patterns: [String: String],
                 equipment: EquipmentCatalog, checkIn: CheckInDefaults) {
        self.programs = programs; self.library = library; self.patterns = patterns
        self.equipment = equipment; self.checkIn = checkIn
    }

    /// The same content with the user's own exercises added to the library. Built-in ids always win.
    public func adding(_ extra: [Exercise]) -> BundledContent {
        guard !extra.isEmpty else { return self }
        var lib = library
        for e in extra where lib[e.id] == nil { lib[e.id] = e }
        return BundledContent(programs: programs, library: lib, patterns: patterns, equipment: equipment, checkIn: checkIn)
    }

    /// Muscle ids used by the built-in exercises, sorted by name.
    public var muscleIds: [String] {
        Array(Set(library.values.filter { !$0.isCustom }.flatMap { $0.primaryMuscles + $0.secondaryMuscles })).sorted()
    }

    public func program(_ id: String) -> Program? { programs.first { $0.id == id } }

    /// What users can choose from. Retired programs never appear; draft (unreviewed) programs appear only in internal builds.
    public func catalogue(showDraft: Bool) -> [Program] {
        programs.filter { $0.catalogue != "legacy" && (showDraft || !$0.isDraft) }
    }
}
