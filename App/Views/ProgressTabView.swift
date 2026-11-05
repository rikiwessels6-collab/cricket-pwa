import SwiftUI
import SwiftData
import Charts
import SteadyCore

/// Progress: your weight trend, weekly check-ins and tape measurements.
struct ProgressTabView: View {
    @Environment(ContentStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \CheckInEntry.date, order: .reverse) private var entries: [CheckInEntry]
    @Query private var settings: [CheckInSettings]
    @Query private var profiles: [UserProfile]
    @State private var checkingIn = false

    private var weights: [WeightPoint] {
        entries.compactMap { e in e.weightKg.map { WeightPoint(date: e.date, kg: $0) } }
    }
    private var due: Bool {
        guard let s = settings.first else { return false }
        return CheckInMath.isDue(weekday: s.weekday, lastCheckIn: entries.first?.date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { checkingIn = true } label: {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(due ? "Weekly check-in is due" : "Add a check-in").font(.headline)
                                Text("Weight, sleep, steps and how you feel. All optional.").font(.footnote).foregroundStyle(Color.inkMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.inkMuted)
                        }
                        .foregroundStyle(due ? Color.gold : Color.ink)
                    }
                    .accessibilityIdentifier("startCheckIn")
                }
                Section("Strength and history") {
                    NavigationLink { StrengthListView() } label: { Label("Lifts and records", systemImage: "chart.line.uptrend.xyaxis") }
                        .accessibilityIdentifier("liftsAndRecords")
                    NavigationLink { WeeklyVolumeView() } label: { Label("Weekly volume", systemImage: "chart.bar.fill") }
                        .accessibilityIdentifier("weeklyVolume")
                    NavigationLink { ProgressPhotosView() } label: { Label("Progress photos", systemImage: "person.crop.rectangle") }
                        .accessibilityIdentifier("progressPhotos")
                    NavigationLink { WorkoutHistoryView() } label: { Label("Workout history", systemImage: "calendar") }
                        .accessibilityIdentifier("workoutHistory")
                }
                HealthActivitySection()
                Section("Weight trend") { weightSection }
                if let m = measurementSummary { Section("Measurements") { m } }
                Section("Check-ins") {
                    if entries.isEmpty {
                        Text("Your check-ins appear here.").font(.footnote).foregroundStyle(Color.inkMuted)
                    }
                    ForEach(entries) { e in
                        NavigationLink { CheckInDetail(entry: e) } label: { row(e) }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(entries[i]) }
                        try? context.save()
                    }
                }
            }
            .themedList()
            .navigationTitle("Progress")
            .sheet(isPresented: $checkingIn) {
                if let content = store.content {
                    CheckInSheet(content: content, settings: settings.first, startWeight: entries.first(where: { $0.weightKg != nil })?.weightKg ?? profiles.first?.weightKg)
                }
            }
        }
    }

    @ViewBuilder private var weightSection: some View {
        let pts = weights
        if pts.count < 2 {
            VStack(alignment: .leading, spacing: 6) {
                if let latest = pts.first { Text(String(format: "%.1f kg", latest.kg)).font(.title2.weight(.semibold).monospacedDigit()) }
                Text("Two or more weigh-ins draw your trend. Weigh at the same time of day when you can.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            }
        } else {
            let smooth = WeightTrend.smoothed(pts)
            Chart {
                ForEach(pts.indices, id: \.self) { i in
                    PointMark(x: .value("Date", pts[i].date), y: .value("kg", pts[i].kg))
                        .foregroundStyle(Color.inkMuted.opacity(0.6)).symbolSize(28)
                }
                ForEach(smooth.indices, id: \.self) { i in
                    LineMark(x: .value("Date", smooth[i].date), y: .value("Trend", smooth[i].kg))
                        .foregroundStyle(Color.gold).interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            .accessibilityLabel("Weight chart")
            Text(WeightTrend.describe(weeklyChange: WeightTrend.weeklyChange(pts)))
                .font(.footnote).foregroundStyle(Color.inkMuted)
            Text("Weight moves day to day with water and food. The gold line smooths that out.")
                .font(.caption2).foregroundStyle(Color.inkMuted)
        }
    }

    private var measurementSummary: AnyView? {
        let withTape = entries.filter { CheckInMath.measurementTotal($0.measurements) > 0 }
        guard let latest = withTape.first else { return nil }
        let total = CheckInMath.measurementTotal(latest.measurements)
        var text = String(format: "%.1f cm total", total)
        if withTape.count > 1 {
            let diff = total - CheckInMath.measurementTotal(withTape[1].measurements)
            text += String(format: " (%+.1f since last time)", diff)
        }
        return AnyView(Text(text).font(.body.monospacedDigit()))
    }

    private func row(_ e: CheckInEntry) -> some View {
        HStack {
            Text(e.date.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            if let w = e.weightKg { Text(String(format: "%.1f kg", w)).monospacedDigit().foregroundStyle(Color.inkMuted) }
        }
    }
}

struct CheckInDetail: View {
    let entry: CheckInEntry
    var body: some View {
        List {
            Section {
                if let w = entry.weightKg { LabeledContent("Weight", value: String(format: "%.1f kg", w)) }
                if let s = entry.sleepHours { LabeledContent("Sleep (average)", value: String(format: "%.1f h", s)) }
                if let s = entry.steps { LabeledContent("Steps (average)", value: s.formatted()) }
                if let n = entry.healthWorkoutCount { LabeledContent("Workouts (from Health)", value: "\(n)") }
                if let m = entry.activeMinutes { LabeledContent("Active minutes (from Health)", value: "\(m)") }
            }
            if !entry.ratings.isEmpty {
                Section("How you felt (1-10)") {
                    ForEach(entry.ratings.keys.sorted(), id: \.self) { LabeledContent($0, value: "\(entry.ratings[$0] ?? 0)") }
                }
            }
            if !entry.measurements.isEmpty {
                Section("Measurements (cm)") {
                    ForEach(entry.measurements.keys.sorted(), id: \.self) { LabeledContent($0, value: String(format: "%.1f", entry.measurements[$0] ?? 0)) }
                }
            }
            if !entry.note.isEmpty { Section("Note") { Text(entry.note) } }
        }
        .themedList()
        .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CheckInSheet: View {
    let content: BundledContent
    let settings: CheckInSettings?
    let startWeight: Double?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var appSettings: [AppSettings]
    @State private var healthNote: String?
    @State private var activeMinutes: Int?
    @State private var workoutCount: Int?
    @State private var date = Date.now
    @State private var weight: Double?
    @State private var sleep: Double?
    @State private var steps: Int?
    @State private var ratings: [String: Int] = [:]
    @State private var tape: [String: Double] = [:]
    @State private var note = ""
    @FocusState private var focused: Bool

    private var metrics: [String] { settings?.metrics ?? content.checkIn.customMetricsDefault }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    numberRow("Weight", "kg", $weight)
                    numberRow("Sleep (average a night)", "h", $sleep)
                    HStack {
                        Text("Steps (average a day)")
                        TextField("steps", value: $steps, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .focused($focused)
                    }
                }
                if appSettings.first?.consents[DataType.appleHealth.rawValue] != nil {
                    Section {
                        Button {
                            Task {
                                let steps = await HealthService.averageDailySteps()
                                let kg = await HealthService.latestWeightKg()
                                let workouts = await HealthService.recentWorkouts(days: 7)
                                let sleepAverage = SleepMath.average(await HealthService.nightlySleep(days: 7))
                                if let sleepAverage { sleep = (sleepAverage * 10).rounded() / 10 }
                                if let steps { self.steps = steps }
                                if let kg { weight = (kg * 10).rounded() / 10 }
                                if !workouts.isEmpty {
                                    workoutCount = workouts.count
                                    activeMinutes = workouts.reduce(0) { $0 + $1.minutes }
                                }
                                healthNote = (steps == nil && kg == nil && workouts.isEmpty && sleepAverage == nil)
                                    ? "Nothing found in Apple Health. Check Health > Data Access for Steady Strength."
                                    : "Filled in from Apple Health"
                                        + (workouts.isEmpty ? "" : " (\(workouts.count) workout\(workouts.count == 1 ? "" : "s"), \(workouts.reduce(0) { $0 + $1.minutes }) active minutes this week)")
                                        + ". Check the numbers and edit anything."
                            }
                        } label: { Label("Fill from Apple Health", systemImage: "heart.text.square") }
                        .accessibilityIdentifier("fillFromHealth")
                        if let healthNote { Text(healthNote).font(.footnote).foregroundStyle(Color.inkMuted) }
                    }
                }
                Section("How did the week feel? (1-10)") {
                    ForEach(metrics, id: \.self) { m in
                        Stepper(value: Binding(get: { ratings[m] ?? 5 }, set: { ratings[m] = $0 }), in: 1...10) {
                            LabeledContent(m, value: ratings[m].map { String($0) } ?? "–")
                        }
                    }
                }
                Section {
                    ForEach(content.checkIn.measurementSites, id: \.self) { site in
                        numberRow(site, "cm", Binding(get: { tape[site] }, set: { tape[site] = $0 }))
                    }
                } header: { Text("Measurements (optional)") } footer: {
                    Text("Measure at the same spots each time, relaxed, without pulling the tape tight.")
                }
                Section("Note") { TextField("Anything worth remembering", text: $note, axis: .vertical).lineLimit(1...4) }
            }
            .themedList()
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).accessibilityIdentifier("saveCheckIn") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            }
            .onAppear { if weight == nil { weight = startWeight } }
        }
    }

    private func numberRow(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            TextField(unit, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused)
            Text(unit).foregroundStyle(Color.inkMuted)
        }
    }

    private func save() {
        let tapClean = tape.filter { $0.value > 0 }
        let entry = CheckInEntry(date: date, weightKg: weight.flatMap { $0 > 0 ? $0 : nil }, sleepHours: sleep, steps: steps,
                                 ratings: ratings, measurements: tapClean, note: note)
        entry.activeMinutes = activeMinutes
        entry.healthWorkoutCount = workoutCount
        context.insert(entry)
        if let w = entry.weightKg, let p = profiles.first, Calendar.current.isDateInToday(date) { p.weightKg = w }
        try? context.save()
        dismiss()
    }
}


/// Your week from Apple Health: steps each day, workouts and active minutes, next to what you do in the app.
struct HealthActivitySection: View {
    @Query private var appSettings: [AppSettings]
    @State private var days: [HealthService.DailySteps] = []
    @State private var workouts: [HealthService.Workout] = []
    @State private var nights: [SleepNight] = []
    @State private var loaded = false

    private var enabled: Bool { appSettings.first?.consents[DataType.appleHealth.rawValue] != nil }

    var body: some View {
        Section {
            if !enabled {
                Text("Turn on Apple Health in Settings to see your steps and activities here.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            } else if !loaded {
                ProgressView()
            } else if days.allSatisfy({ $0.steps == 0 }) && workouts.isEmpty && nights.isEmpty {
                Text("Nothing found in Apple Health for the last 7 days. Check Health > Data Access for Steady Strength.")
                    .font(.footnote).foregroundStyle(Color.inkMuted)
            } else {
                let withData = days.filter { $0.steps > 0 }
                let average = withData.isEmpty ? 0 : withData.map(\.steps).reduce(0, +) / withData.count
                let minutes = workouts.reduce(0) { $0 + $1.minutes }
                HStack(spacing: 0) {
                    stat(average.formatted(), "avg steps a day")
                    stat("\(workouts.count)", "workouts")
                    stat("\(minutes)", "active min")
                    stat(SleepMath.average(nights).map { String(format: "%.1f h", $0) } ?? "–", "avg sleep")
                }
                Chart(days) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Steps", d.steps))
                        .foregroundStyle(Color.emerald)
                }
                .frame(height: 120)
                .accessibilityLabel("Steps each day for the last 7 days")
                if !nights.isEmpty {
                    Chart(nights) { n in
                        BarMark(x: .value("Night", n.night, unit: .day), y: .value("Hours", n.hours))
                            .foregroundStyle(Color.gold)
                    }
                    .frame(height: 100)
                    .accessibilityLabel("Hours asleep each night for the last 7 nights")
                    Text("Gold bars are hours asleep each night.").font(.caption2).foregroundStyle(Color.inkMuted)
                }
                ForEach(workouts) { w in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).foregroundStyle(Color.ink)
                            Text(w.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                .font(.caption).foregroundStyle(Color.inkMuted)
                        }
                        Spacer()
                        Text("\(w.minutes) min" + (w.kcal.map { " · \($0) kcal" } ?? ""))
                            .font(.footnote.monospacedDigit()).foregroundStyle(Color.inkMuted)
                    }
                }
            }
        } header: { Text("This week from Apple Health") } footer: {
            if enabled { Text("Read from Apple Health on this phone. It includes workouts recorded by your watch and other apps. Nothing is written back or shared.") }
        }
        .task(id: enabled) {
            guard enabled else { return }
            _ = await HealthService.requestAccess()
            async let d = HealthService.dailySteps(days: 7)
            async let w = HealthService.recentWorkouts(days: 7)
            async let sl = HealthService.nightlySleep(days: 7)
            days = await d
            workouts = await w
            nights = await sl
            loaded = true
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.ink)
            Text(label).font(.caption2).foregroundStyle(Color.inkMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
